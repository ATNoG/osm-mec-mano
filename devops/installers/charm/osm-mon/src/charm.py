#!/usr/bin/env python3
# Copyright 2022 Canonical Ltd.
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
#
#
# Learn more at: https://juju.is/docs/sdk

"""OSM MON charm.

See more: https://charmhub.io/osm
"""

import logging
from typing import Any, Dict

from charms.data_platform_libs.v0.data_interfaces import DatabaseRequires
from charms.kafka_k8s.v0.kafka import KafkaRequires, _KafkaAvailableEvent
from charms.observability_libs.v1.kubernetes_service_patch import KubernetesServicePatch
from charms.osm_libs.v0.utils import (
    CharmError,
    DebugMode,
    HostPath,
    check_container_ready,
    check_service_active,
)
from charms.osm_vca_integrator.v0.vca import VcaDataChangedEvent, VcaRequires
from lightkube.models.core_v1 import ServicePort
from ops.charm import ActionEvent, CharmBase, CharmEvents
from ops.framework import EventSource, StoredState
from ops.main import main
from ops.model import ActiveStatus, Container

from legacy_interfaces import KeystoneClient, PrometheusClient

HOSTPATHS = [
    HostPath(
        config="mon-hostpath",
        container_path="/usr/lib/python3/dist-packages/osm_mon",
    ),
    HostPath(
        config="common-hostpath",
        container_path="/usr/lib/python3/dist-packages/osm_common",
    ),
    HostPath(
        config="n2vc-hostpath",
        container_path="/usr/lib/python3/dist-packages/n2vc",
    ),
]
SERVICE_PORT = 8000

logger = logging.getLogger(__name__)


class MonEvents(CharmEvents):
    """MON events."""

    vca_data_changed = EventSource(VcaDataChangedEvent)
    kafka_available = EventSource(_KafkaAvailableEvent)


class OsmMonCharm(CharmBase):
    """OSM MON Kubernetes sidecar charm."""

    on = MonEvents()
    _stored = StoredState()
    container_name = "mon"
    service_name = "mon"

    def __init__(self, *args):
        super().__init__(*args)
        self.kafka = KafkaRequires(self)
        self.mongodb_client = DatabaseRequires(self, "mongodb", database_name="osm")
        self.prometheus_client = PrometheusClient(self, "prometheus")
        self.keystone_client = KeystoneClient(self, "keystone")
        self.vca = VcaRequires(self)
        self._observe_charm_events()
        self.container: Container = self.unit.get_container(self.container_name)
        self.debug_mode = DebugMode(self, self._stored, self.container, HOSTPATHS)
        self._patch_k8s_service()

    @property
    def external_hostname(self) -> str:
        """External hostname property.

        Returns:
            str: the external hostname from config.
                If not set, return the ClusterIP service name.
        """
        return self.config.get("external-hostname") or self.app.name

    # ---------------------------------------------------------------------------
    #   Handlers for Charm Events
    # ---------------------------------------------------------------------------

    def _on_config_changed(self, _) -> None:
        """Handler for the config-changed event."""
        try:
            self._validate_config()
            self._check_relations()
            # Check if the container is ready.
            # Eventually it will become ready after the first pebble-ready event.
            check_container_ready(self.container)
            if not self.debug_mode.started:
                self._configure_service(self.container)
            # Update charm status
            self._on_update_status()
        except CharmError as e:
            logger.debug(e.message)
            self.unit.status = e.status

    def _on_update_status(self, _=None) -> None:
        """Handler for the update-status event."""
        try:
            self._validate_config()
            self._check_relations()
            check_container_ready(self.container)
            if self.debug_mode.started:
                return
            check_service_active(self.container, self.service_name)
            self.unit.status = ActiveStatus()
        except CharmError as e:
            logger.debug(e.message)
            self.unit.status = e.status

    def _on_required_relation_broken(self, _) -> None:
        """Handler for the kafka-broken event."""
        try:
            check_container_ready(self.container)
            check_service_active(self.container, self.service_name)
            self.container.stop(self.container_name)
        except CharmError:
            pass
        self._on_update_status()

    def _on_get_debug_mode_information_action(self, event: ActionEvent) -> None:
        """Handler for the get-debug-mode-information action event."""
        if not self.debug_mode.started:
            event.fail("debug-mode has not started. Hint: juju config mon debug-mode=true")
            return

        debug_info = {
            "command": self.debug_mode.command,
            "password": self.debug_mode.password,
        }
        event.set_results(debug_info)

    # ---------------------------------------------------------------------------
    #   Validation and configuration and more
    # ---------------------------------------------------------------------------

    def _observe_charm_events(self) -> None:
        event_handler_mapping = {
            # Core lifecycle events
            self.on.mon_pebble_ready: self._on_config_changed,
            self.on.config_changed: self._on_config_changed,
            self.on.update_status: self._on_update_status,
            # Relation events
            self.on.vca_data_changed: self._on_config_changed,
            self.on.kafka_available: self._on_config_changed,
            self.on["kafka"].relation_broken: self._on_required_relation_broken,
            self.mongodb_client.on.database_created: self._on_config_changed,
            self.on["mongodb"].relation_broken: self._on_required_relation_broken,
            # Action events
            self.on.get_debug_mode_information_action: self._on_get_debug_mode_information_action,
        }
        for relation in [self.on[rel_name] for rel_name in ["prometheus", "keystone"]]:
            event_handler_mapping[relation.relation_changed] = self._on_config_changed
            event_handler_mapping[relation.relation_broken] = self._on_required_relation_broken

        for event, handler in event_handler_mapping.items():
            self.framework.observe(event, handler)

    def _is_database_available(self) -> bool:
        try:
            return self.mongodb_client.is_resource_created()
        except KeyError:
            return False

    def _validate_config(self) -> None:
        """Validate charm configuration.

        Raises:
            CharmError: if charm configuration is invalid.
        """
        logger.debug("validating charm config")

    def _check_relations(self) -> None:
        """Validate charm relations.

        Raises:
            CharmError: if charm configuration is invalid.
        """
        logger.debug("check for missing relations")
        missing_relations = []

        if not self.kafka.host or not self.kafka.port:
            missing_relations.append("kafka")
        if not self._is_database_available():
            missing_relations.append("mongodb")
        if self.prometheus_client.is_missing_data_in_app():
            missing_relations.append("prometheus")
        if self.keystone_client.is_missing_data_in_app():
            missing_relations.append("keystone")

        if missing_relations:
            relations_str = ", ".join(missing_relations)
            one_relation_missing = len(missing_relations) == 1
            error_msg = f'need {relations_str} relation{"" if one_relation_missing else "s"}'
            logger.warning(error_msg)
            raise CharmError(error_msg)

    def _configure_service(self, container: Container) -> None:
        """Add Pebble layer with the mon service."""
        logger.debug(f"configuring {self.app.name} service")
        container.add_layer("mon", self._get_layer(), combine=True)
        container.replan()

    def _get_layer(self) -> Dict[str, Any]:
        """Get layer for Pebble."""
        environment = {
            # General configuration
            "OSMMON_GLOBAL_LOGLEVEL": self.config["log-level"],
            "OSMMON_OPENSTACK_DEFAULT_GRANULARITY": self.config["openstack-default-granularity"],
            "OSMMON_GLOBAL_REQUEST_TIMEOUT": self.config["global-request-timeout"],
            "OSMMON_COLLECTOR_INTERVAL": self.config["collector-interval"],
            "OSMMON_EVALUATOR_INTERVAL": self.config["evaluator-interval"],
            "OSMMON_COLLECTOR_VM_INFRA_METRICS": self.config["vm-infra-metrics"],
            # Kafka configuration
            "OSMMON_MESSAGE_DRIVER": "kafka",
            "OSMMON_MESSAGE_HOST": self.kafka.host,
            "OSMMON_MESSAGE_PORT": self.kafka.port,
            # Database configuration
            "OSMMON_DATABASE_DRIVER": "mongo",
            "OSMMON_DATABASE_URI": self._get_mongodb_uri(),
            "OSMMON_DATABASE_COMMONKEY": self.config["database-commonkey"],
            # Prometheus/grafana configuration
            "OSMMON_PROMETHEUS_URL": f"http://{self.prometheus_client.hostname}:{self.prometheus_client.port}",
            "OSMMON_PROMETHEUS_USER": self.prometheus_client.user,
            "OSMMON_PROMETHEUS_PASSWORD": self.prometheus_client.password,
            "OSMMON_GRAFANA_URL": self.config["grafana-url"],
            "OSMMON_GRAFANA_USER": self.config["grafana-user"],
            "OSMMON_GRAFANA_PASSWORD": self.config["grafana-password"],
            "OSMMON_KEYSTONE_ENABLED": self.config["keystone-enabled"],
            "OSMMON_KEYSTONE_URL": self.keystone_client.host,
            "OSMMON_KEYSTONE_DOMAIN_NAME": self.keystone_client.user_domain_name,
            "OSMMON_KEYSTONE_SERVICE_PROJECT": self.keystone_client.service,
            "OSMMON_KEYSTONE_SERVICE_USER": self.keystone_client.username,
            "OSMMON_KEYSTONE_SERVICE_PASSWORD": self.keystone_client.password,
            "OSMMON_KEYSTONE_SERVICE_PROJECT_DOMAIN_NAME": self.keystone_client.project_domain_name,
        }
        logger.info(f"{environment}")
        if self.vca.data:
            environment["OSMMON_VCA_HOST"] = self.vca.data.endpoints
            environment["OSMMON_VCA_SECRET"] = self.vca.data.secret
            environment["OSMMON_VCA_USER"] = self.vca.data.user
            environment["OSMMON_VCA_CACERT"] = self.vca.data.cacert
        return {
            "summary": "mon layer",
            "description": "pebble config layer for mon",
            "services": {
                self.service_name: {
                    "override": "replace",
                    "summary": "mon service",
                    "command": "/bin/bash -c 'cd /app/osm_mon/ && /bin/bash start.sh'",
                    "startup": "enabled",
                    "user": "appuser",
                    "group": "appuser",
                    "working-dir": "/app/osm_mon",  # This parameter has no effect in Juju 2.9.x
                    "environment": environment,
                }
            },
        }

    def _get_mongodb_uri(self):
        return list(self.mongodb_client.fetch_relation_data().values())[0]["uris"]

    def _patch_k8s_service(self) -> None:
        port = ServicePort(SERVICE_PORT, name=f"{self.app.name}")
        self.service_patcher = KubernetesServicePatch(self, [port])


if __name__ == "__main__":  # pragma: no cover
    main(OsmMonCharm)
