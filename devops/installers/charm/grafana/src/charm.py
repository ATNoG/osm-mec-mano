#!/usr/bin/env python3
# Copyright 2021 Canonical Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
#
# For those usages not covered by the Apache License, Version 2.0 please
# contact: legal@canonical.com
#
# To get in touch with the maintainers, please contact:
# osm-charmers@lists.launchpad.net
##

# pylint: disable=E0213

from ipaddress import ip_network
import logging
from pathlib import Path
import secrets
from string import Template
from typing import NoReturn, Optional
from urllib.parse import urlparse

from ops.main import main
from opslib.osm.charm import CharmedOsmBase, RelationsMissing
from opslib.osm.interfaces.grafana import GrafanaCluster
from opslib.osm.interfaces.mysql import MysqlClient
from opslib.osm.interfaces.prometheus import PrometheusClient
from opslib.osm.pod import (
    ContainerV3Builder,
    FilesV3Builder,
    IngressResourceV3Builder,
    PodRestartPolicy,
    PodSpecV3Builder,
)
from opslib.osm.validator import ModelValidator, validator


logger = logging.getLogger(__name__)


class ConfigModel(ModelValidator):
    log_level: str
    port: int
    admin_user: str
    max_file_size: int
    osm_dashboards: bool
    site_url: Optional[str]
    cluster_issuer: Optional[str]
    ingress_class: Optional[str]
    ingress_whitelist_source_range: Optional[str]
    tls_secret_name: Optional[str]
    image_pull_policy: str
    security_context: bool

    @validator("log_level")
    def validate_log_level(cls, v):
        allowed_values = ("debug", "info", "warn", "error", "critical")
        if v not in allowed_values:
            separator = '", "'
            raise ValueError(
                f'incorrect value. Allowed values are "{separator.join(allowed_values)}"'
            )
        return v

    @validator("max_file_size")
    def validate_max_file_size(cls, v):
        if v < 0:
            raise ValueError("value must be equal or greater than 0")
        return v

    @validator("site_url")
    def validate_site_url(cls, v):
        if v:
            parsed = urlparse(v)
            if not parsed.scheme.startswith("http"):
                raise ValueError("value must start with http")
        return v

    @validator("ingress_whitelist_source_range")
    def validate_ingress_whitelist_source_range(cls, v):
        if v:
            ip_network(v)
        return v

    @validator("image_pull_policy")
    def validate_image_pull_policy(cls, v):
        values = {
            "always": "Always",
            "ifnotpresent": "IfNotPresent",
            "never": "Never",
        }
        v = v.lower()
        if v not in values.keys():
            raise ValueError("value must be always, ifnotpresent or never")
        return values[v]


class GrafanaCharm(CharmedOsmBase):
    """GrafanaCharm Charm."""

    def __init__(self, *args) -> NoReturn:
        """Prometheus Charm constructor."""
        super().__init__(*args, oci_image="image", mysql_uri=True)
        # Initialize relation objects
        self.prometheus_client = PrometheusClient(self, "prometheus")
        self.grafana_cluster = GrafanaCluster(self, "cluster")
        self.mysql_client = MysqlClient(self, "db")
        # Observe events
        event_observer_mapping = {
            self.on["prometheus"].relation_changed: self.configure_pod,
            self.on["prometheus"].relation_broken: self.configure_pod,
            self.on["db"].relation_changed: self.configure_pod,
            self.on["db"].relation_broken: self.configure_pod,
        }
        for event, observer in event_observer_mapping.items():
            self.framework.observe(event, observer)

    def _build_dashboard_files(self, config: ConfigModel):
        files_builder = FilesV3Builder()
        files_builder.add_file(
            "dashboard_osm.yaml",
            Path("templates/default_dashboards.yaml").read_text(),
        )
        if config.osm_dashboards:
            osm_dashboards_mapping = {
                "kafka_exporter_dashboard.json": "templates/kafka_exporter_dashboard.json",
                "mongodb_exporter_dashboard.json": "templates/mongodb_exporter_dashboard.json",
                "mysql_exporter_dashboard.json": "templates/mysql_exporter_dashboard.json",
                "nodes_exporter_dashboard.json": "templates/nodes_exporter_dashboard.json",
                "summary_dashboard.json": "templates/summary_dashboard.json",
            }
            for file_name, path in osm_dashboards_mapping.items():
                files_builder.add_file(file_name, Path(path).read_text())
        return files_builder.build()

    def _build_datasources_files(self):
        files_builder = FilesV3Builder()
        prometheus_user = self.prometheus_client.user
        prometheus_password = self.prometheus_client.password
        enable_basic_auth = all([prometheus_user, prometheus_password])
        kwargs = {
            "prometheus_host": self.prometheus_client.hostname,
            "prometheus_port": self.prometheus_client.port,
            "enable_basic_auth": enable_basic_auth,
            "user": "",
            "password": "",
        }
        if enable_basic_auth:
            kwargs["user"] = f"basic_auth_user: {prometheus_user}"
            kwargs[
                "password"
            ] = f"secure_json_data:\n      basicAuthPassword: {prometheus_password}"
        files_builder.add_file(
            "datasource_prometheus.yaml",
            Template(Path("templates/default_datasources.yaml").read_text()).substitute(
                **kwargs
            ),
        )
        return files_builder.build()

    def _check_missing_dependencies(self, config: ConfigModel, external_db: bool):
        missing_relations = []

        if self.prometheus_client.is_missing_data_in_app():
            missing_relations.append("prometheus")

        if not external_db and self.mysql_client.is_missing_data_in_unit():
            missing_relations.append("db")

        if missing_relations:
            raise RelationsMissing(missing_relations)

    def build_pod_spec(self, image_info, **kwargs):
        # Validate config
        config = ConfigModel(**dict(self.config))
        mysql_config = kwargs["mysql_config"]
        if mysql_config.mysql_uri and not self.mysql_client.is_missing_data_in_unit():
            raise Exception("Mysql data cannot be provided via config and relation")

        # Check relations
        external_db = True if mysql_config.mysql_uri else False
        self._check_missing_dependencies(config, external_db)

        # Get initial password
        admin_initial_password = self.grafana_cluster.admin_initial_password
        if not admin_initial_password:
            admin_initial_password = _generate_random_password()
            self.grafana_cluster.set_initial_password(admin_initial_password)

        # Create Builder for the PodSpec
        pod_spec_builder = PodSpecV3Builder(
            enable_security_context=config.security_context
        )

        # Add secrets to the pod
        grafana_secret_name = f"{self.app.name}-admin-secret"
        pod_spec_builder.add_secret(
            grafana_secret_name,
            {
                "admin-password": admin_initial_password,
                "mysql-url": mysql_config.mysql_uri or self.mysql_client.get_uri(),
                "prometheus-user": self.prometheus_client.user,
                "prometheus-password": self.prometheus_client.password,
            },
        )

        # Build Container
        container_builder = ContainerV3Builder(
            self.app.name,
            image_info,
            config.image_pull_policy,
            run_as_non_root=config.security_context,
        )
        container_builder.add_port(name=self.app.name, port=config.port)
        container_builder.add_http_readiness_probe(
            "/api/health",
            config.port,
            initial_delay_seconds=10,
            period_seconds=10,
            timeout_seconds=5,
            failure_threshold=3,
        )
        container_builder.add_http_liveness_probe(
            "/api/health",
            config.port,
            initial_delay_seconds=60,
            timeout_seconds=30,
            failure_threshold=10,
        )
        container_builder.add_volume_config(
            "dashboards",
            "/etc/grafana/provisioning/dashboards/",
            self._build_dashboard_files(config),
        )
        container_builder.add_volume_config(
            "datasources",
            "/etc/grafana/provisioning/datasources/",
            self._build_datasources_files(),
        )
        container_builder.add_envs(
            {
                "GF_SERVER_HTTP_PORT": config.port,
                "GF_LOG_LEVEL": config.log_level,
                "GF_SECURITY_ADMIN_USER": config.admin_user,
            }
        )
        container_builder.add_secret_envs(
            secret_name=grafana_secret_name,
            envs={
                "GF_SECURITY_ADMIN_PASSWORD": "admin-password",
                "GF_DATABASE_URL": "mysql-url",
                "PROMETHEUS_USER": "prometheus-user",
                "PROMETHEUS_PASSWORD": "prometheus-password",
            },
        )
        container = container_builder.build()
        pod_spec_builder.add_container(container)

        # Add Pod restart policy
        restart_policy = PodRestartPolicy()
        restart_policy.add_secrets(secret_names=(grafana_secret_name,))
        pod_spec_builder.set_restart_policy(restart_policy)

        # Add ingress resources to pod spec if site url exists
        if config.site_url:
            parsed = urlparse(config.site_url)
            annotations = {
                "nginx.ingress.kubernetes.io/proxy-body-size": "{}".format(
                    str(config.max_file_size) + "m"
                    if config.max_file_size > 0
                    else config.max_file_size
                )
            }
            if config.ingress_class:
                annotations["kubernetes.io/ingress.class"] = config.ingress_class
            ingress_resource_builder = IngressResourceV3Builder(
                f"{self.app.name}-ingress", annotations
            )

            if config.ingress_whitelist_source_range:
                annotations[
                    "nginx.ingress.kubernetes.io/whitelist-source-range"
                ] = config.ingress_whitelist_source_range

            if config.cluster_issuer:
                annotations["cert-manager.io/cluster-issuer"] = config.cluster_issuer

            if parsed.scheme == "https":
                ingress_resource_builder.add_tls(
                    [parsed.hostname], config.tls_secret_name
                )
            else:
                annotations["nginx.ingress.kubernetes.io/ssl-redirect"] = "false"

            ingress_resource_builder.add_rule(
                parsed.hostname, self.app.name, config.port
            )
            ingress_resource = ingress_resource_builder.build()
            pod_spec_builder.add_ingress_resource(ingress_resource)
        return pod_spec_builder.build()


def _generate_random_password():
    return secrets.token_hex(16)


if __name__ == "__main__":
    main(GrafanaCharm)
