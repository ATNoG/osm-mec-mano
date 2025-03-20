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

"""OSM NBI charm.

See more: https://charmhub.io/osm
"""

import logging
from typing import Any, Dict

from charms.data_platform_libs.v0.data_interfaces import DatabaseRequires
from charms.kafka_k8s.v0.kafka import KafkaEvents, KafkaRequires
from charms.nginx_ingress_integrator.v0.ingress import IngressRequires
from charms.observability_libs.v1.kubernetes_service_patch import KubernetesServicePatch
from charms.osm_libs.v0.utils import (
    CharmError,
    DebugMode,
    HostPath,
    check_container_ready,
    check_service_active,
)
from charms.osm_nbi.v0.nbi import NbiProvides
from lightkube.models.core_v1 import ServicePort
from ops.charm import ActionEvent, CharmBase, RelationJoinedEvent
from ops.framework import StoredState
from ops.main import main
from ops.model import ActiveStatus, Container

from legacy_interfaces import KeystoneClient, PrometheusClient

HOSTPATHS = [
    HostPath(
        config="nbi-hostpath",
        container_path="/usr/lib/python3/dist-packages/osm_nbi",
    ),
    HostPath(
        config="common-hostpath",
        container_path="/usr/lib/python3/dist-packages/osm_common",
    ),
]
SERVICE_PORT = 9999

logger = logging.getLogger(__name__)


class OsmNbiCharm(CharmBase):
    """OSM NBI Kubernetes sidecar charm."""

    on = KafkaEvents()
    _stored = StoredState()

    def __init__(self, *args):
        super().__init__(*args)
        self.ingress = IngressRequires(
            self,
            {
                "service-hostname": self.external_hostname,
                "service-name": self.app.name,
                "service-port": SERVICE_PORT,
            },
        )
        self.kafka = KafkaRequires(self)
        self.nbi = NbiProvides(self)
        self.mongodb_client = DatabaseRequires(
            self, "mongodb", database_name="osm", extra_user_roles="admin"
        )
        self.prometheus_client = PrometheusClient(self, "prometheus")
        self.keystone_client = KeystoneClient(self, "keystone")
        self._observe_charm_events()
        self.container: Container = self.unit.get_container("nbi")
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
            self._update_ingress_config()
            self._update_nbi_relation()
            # Update charm status
            self._on_update_status()
        except CharmError as e:
            logger.debug(e.message)
            self.unit.status = e.status

    def _on_update_status(self, _=None) -> None:
        """Handler for the update-status event."""
        try:
            self._check_relations()
            if self.debug_mode.started:
                return
            check_container_ready(self.container)
            check_service_active(self.container, "nbi")
            self.unit.status = ActiveStatus()
        except CharmError as e:
            logger.debug(e.message)
            self.unit.status = e.status

    def _on_required_relation_broken(self, _) -> None:
        """Handler for the kafka-broken event."""
        # Check Pebble has started in the container
        try:
            check_container_ready(self.container)
            check_service_active(self.container, "nbi")
            self.container.stop("nbi")
        except CharmError:
            pass
        finally:
            self._on_update_status()

    def _update_nbi_relation(self, event: RelationJoinedEvent = None) -> None:
        """Handler for the nbi-relation-joined event."""
        if self.unit.is_leader():
            self.nbi.set_host_info(self.app.name, SERVICE_PORT, event.relation if event else None)

    def _on_get_debug_mode_information_action(self, event: ActionEvent) -> None:
        """Handler for the get-debug-mode-information action event."""
        if not self.debug_mode.started:
            event.fail("debug-mode has not started. Hint: juju config nbi debug-mode=true")
            return

        debug_info = {"command": self.debug_mode.command, "password": self.debug_mode.password}
        event.set_results(debug_info)

    # ---------------------------------------------------------------------------
    #   Validation and configuration and more
    # ---------------------------------------------------------------------------

    def _patch_k8s_service(self) -> None:
        port = ServicePort(SERVICE_PORT, name=f"{self.app.name}")
        self.service_patcher = KubernetesServicePatch(self, [port])

    def _observe_charm_events(self) -> None:
        event_handler_mapping = {
            # Core lifecycle events
            self.on.nbi_pebble_ready: self._on_config_changed,
            self.on.config_changed: self._on_config_changed,
            self.on.update_status: self._on_update_status,
            # Relation events
            self.on.kafka_available: self._on_config_changed,
            self.on["kafka"].relation_broken: self._on_required_relation_broken,
            self.mongodb_client.on.database_created: self._on_config_changed,
            self.on["mongodb"].relation_broken: self._on_required_relation_broken,
            # Action events
            self.on.get_debug_mode_information_action: self._on_get_debug_mode_information_action,
            self.on.nbi_relation_joined: self._update_nbi_relation,
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

    def _update_ingress_config(self) -> None:
        """Update ingress config in relation."""
        ingress_config = {
            "service-hostname": self.external_hostname,
            "max-body-size": self.config["max-body-size"],
        }
        if "tls-secret-name" in self.config:
            ingress_config["tls-secret-name"] = self.config["tls-secret-name"]
        logger.debug(f"updating ingress-config: {ingress_config}")
        self.ingress.update_config(ingress_config)

    def _configure_service(self, container: Container) -> None:
        """Add Pebble layer with the nbi service."""
        logger.debug(f"configuring {self.app.name} service")
        container.add_layer("nbi", self._get_layer(), combine=True)
        container.replan()

    def _get_layer(self) -> Dict[str, Any]:
        """Get layer for Pebble."""
        return {
            "summary": "nbi layer",
            "description": "pebble config layer for nbi",
            "services": {
                "nbi": {
                    "override": "replace",
                    "summary": "nbi service",
                    "command": "/bin/sh -c 'cd /app/osm_nbi && python3 -m osm_nbi.nbi'",  # cd /app/osm_nbi is needed until we upgrade Juju to 3.x
                    "startup": "enabled",
                    "user": "appuser",
                    "group": "appuser",
                    "working-dir": "/app/osm_nbi",  # This parameter has no effect in juju 2.9.x
                    "environment": {
                        # General configuration
                        "OSMNBI_SERVER_ENABLE_TEST": False,
                        "OSMNBI_STATIC_DIR": "/app/osm_nbi/html_public",
                        # Kafka configuration
                        "OSMNBI_MESSAGE_HOST": self.kafka.host,
                        "OSMNBI_MESSAGE_PORT": self.kafka.port,
                        "OSMNBI_MESSAGE_DRIVER": "kafka",
                        # Database configuration
                        "OSMNBI_DATABASE_DRIVER": "mongo",
                        "OSMNBI_DATABASE_URI": self._get_mongodb_uri(),
                        "OSMNBI_DATABASE_COMMONKEY": self.config["database-commonkey"],
                        # Storage configuration
                        "OSMNBI_STORAGE_DRIVER": "mongo",
                        "OSMNBI_STORAGE_PATH": "/app/storage",
                        "OSMNBI_STORAGE_COLLECTION": "files",
                        "OSMNBI_STORAGE_URI": self._get_mongodb_uri(),
                        # Prometheus configuration
                        "OSMNBI_PROMETHEUS_HOST": self.prometheus_client.hostname,
                        "OSMNBI_PROMETHEUS_PORT": self.prometheus_client.port,
                        # Log configuration
                        "OSMNBI_LOG_LEVEL": self.config["log-level"],
                        # Authentication environments
                        "OSMNBI_AUTHENTICATION_BACKEND": "keystone",
                        "OSMNBI_AUTHENTICATION_AUTH_URL": self.keystone_client.host,
                        "OSMNBI_AUTHENTICATION_AUTH_PORT": self.keystone_client.port,
                        "OSMNBI_AUTHENTICATION_USER_DOMAIN_NAME": self.keystone_client.user_domain_name,
                        "OSMNBI_AUTHENTICATION_PROJECT_DOMAIN_NAME": self.keystone_client.project_domain_name,
                        "OSMNBI_AUTHENTICATION_SERVICE_USERNAME": self.keystone_client.username,
                        "OSMNBI_AUTHENTICATION_SERVICE_PASSWORD": self.keystone_client.password,
                        "OSMNBI_AUTHENTICATION_SERVICE_PROJECT": self.keystone_client.service,
                        # DISABLING INTERNAL SSL SERVER
                        "OSMNBI_SERVER_SSL_MODULE": "",
                        "OSMNBI_SERVER_SSL_CERTIFICATE": "",
                        "OSMNBI_SERVER_SSL_PRIVATE_KEY": "",
                        "OSMNBI_SERVER_SSL_PASS_PHRASE": "",
                    },
                }
            },
        }

    def _get_mongodb_uri(self):
        return list(self.mongodb_client.fetch_relation_data().values())[0]["uris"]


if __name__ == "__main__":  # pragma: no cover
    main(OsmNbiCharm)
