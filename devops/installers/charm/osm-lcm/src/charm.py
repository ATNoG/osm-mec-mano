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

"""OSM LCM charm.

See more: https://charmhub.io/osm
"""

import logging
from typing import Any, Dict

from charms.data_platform_libs.v0.data_interfaces import DatabaseRequires
from charms.kafka_k8s.v0.kafka import KafkaRequires, _KafkaAvailableEvent
from charms.osm_libs.v0.utils import (
    CharmError,
    DebugMode,
    HostPath,
    check_container_ready,
    check_service_active,
)
from charms.osm_ro.v0.ro import RoRequires
from charms.osm_vca_integrator.v0.vca import VcaDataChangedEvent, VcaRequires
from ops.charm import ActionEvent, CharmBase, CharmEvents
from ops.framework import EventSource, StoredState
from ops.main import main
from ops.model import ActiveStatus, Container

HOSTPATHS = [
    HostPath(
        config="lcm-hostpath",
        container_path="/usr/lib/python3/dist-packages/osm_lcm",
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

logger = logging.getLogger(__name__)


class LcmEvents(CharmEvents):
    """LCM events."""

    vca_data_changed = EventSource(VcaDataChangedEvent)
    kafka_available = EventSource(_KafkaAvailableEvent)


class OsmLcmCharm(CharmBase):
    """OSM LCM Kubernetes sidecar charm."""

    container_name = "lcm"
    service_name = "lcm"
    on = LcmEvents()
    _stored = StoredState()

    def __init__(self, *args):
        super().__init__(*args)
        self.vca = VcaRequires(self)
        self.kafka = KafkaRequires(self)
        self.mongodb_client = DatabaseRequires(
            self, "mongodb", database_name="osm", extra_user_roles="admin"
        )
        self._observe_charm_events()
        self.ro = RoRequires(self)
        self.container: Container = self.unit.get_container(self.container_name)
        self.debug_mode = DebugMode(self, self._stored, self.container, HOSTPATHS)

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
        """Handler for required relation-broken events."""
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
            event.fail(
                f"debug-mode has not started. Hint: juju config {self.app.name} debug-mode=true"
            )
            return

        debug_info = {"command": self.debug_mode.command, "password": self.debug_mode.password}
        event.set_results(debug_info)

    # ---------------------------------------------------------------------------
    #   Validation, configuration and more
    # ---------------------------------------------------------------------------

    def _validate_config(self) -> None:
        """Validate charm configuration.

        Raises:
            CharmError: if charm configuration is invalid.
        """
        logger.debug("validating charm config")
        if self.config["log-level"].upper() not in [
            "TRACE",
            "DEBUG",
            "INFO",
            "WARN",
            "ERROR",
            "FATAL",
        ]:
            raise CharmError("invalid value for log-level option")

    def _observe_charm_events(self) -> None:
        event_handler_mapping = {
            # Core lifecycle events
            self.on.lcm_pebble_ready: self._on_config_changed,
            self.on.config_changed: self._on_config_changed,
            self.on.update_status: self._on_update_status,
            # Relation events
            self.on.kafka_available: self._on_config_changed,
            self.on["kafka"].relation_broken: self._on_required_relation_broken,
            self.mongodb_client.on.database_created: self._on_config_changed,
            self.on["mongodb"].relation_broken: self._on_required_relation_broken,
            self.on["ro"].relation_changed: self._on_config_changed,
            self.on["ro"].relation_broken: self._on_required_relation_broken,
            self.on.vca_data_changed: self._on_config_changed,
            self.on["vca"].relation_broken: self._on_config_changed,
            # Action events
            self.on.get_debug_mode_information_action: self._on_get_debug_mode_information_action,
        }
        for event, handler in event_handler_mapping.items():
            self.framework.observe(event, handler)

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
        if not self.ro.host or not self.ro.port:
            missing_relations.append("ro")

        if missing_relations:
            relations_str = ", ".join(missing_relations)
            one_relation_missing = len(missing_relations) == 1
            error_msg = f'need {relations_str} relation{"" if one_relation_missing else "s"}'
            logger.warning(error_msg)
            raise CharmError(error_msg)

    def _is_database_available(self) -> bool:
        try:
            return self.mongodb_client.is_resource_created()
        except KeyError:
            return False

    def _configure_service(self, container: Container) -> None:
        """Add Pebble layer with the lcm service."""
        logger.debug(f"configuring {self.app.name} service")
        container.add_layer("lcm", self._get_layer(), combine=True)
        container.replan()

    def _get_layer(self) -> Dict[str, Any]:
        """Get layer for Pebble."""
        environments = {
            # General configuration
            "OSMLCM_GLOBAL_LOGLEVEL": self.config["log-level"].upper(),
            # Kafka configuration
            "OSMLCM_MESSAGE_DRIVER": "kafka",
            "OSMLCM_MESSAGE_HOST": self.kafka.host,
            "OSMLCM_MESSAGE_PORT": self.kafka.port,
            # RO configuration
            "OSMLCM_RO_HOST": self.ro.host,
            "OSMLCM_RO_PORT": self.ro.port,
            "OSMLCM_RO_TENANT": "osm",
            # Database configuration
            "OSMLCM_DATABASE_DRIVER": "mongo",
            "OSMLCM_DATABASE_URI": self._get_mongodb_uri(),
            "OSMLCM_DATABASE_COMMONKEY": self.config["database-commonkey"],
            # Storage configuration
            "OSMLCM_STORAGE_DRIVER": "mongo",
            "OSMLCM_STORAGE_PATH": "/app/storage",
            "OSMLCM_STORAGE_COLLECTION": "files",
            "OSMLCM_STORAGE_URI": self._get_mongodb_uri(),
            "OSMLCM_VCA_HELM_CA_CERTS": self.config["helm-ca-certs"],
            "OSMLCM_VCA_STABLEREPOURL": self.config["helm-stable-repo-url"],
        }
        # Vca configuration
        if self.vca.data:
            environments["OSMLCM_VCA_ENDPOINTS"] = self.vca.data.endpoints
            environments["OSMLCM_VCA_USER"] = self.vca.data.user
            environments["OSMLCM_VCA_PUBKEY"] = self.vca.data.public_key
            environments["OSMLCM_VCA_SECRET"] = self.vca.data.secret
            environments["OSMLCM_VCA_CACERT"] = self.vca.data.cacert
            if self.vca.data.lxd_cloud:
                environments["OSMLCM_VCA_CLOUD"] = self.vca.data.lxd_cloud

            if self.vca.data.k8s_cloud:
                environments["OSMLCM_VCA_K8S_CLOUD"] = self.vca.data.k8s_cloud
            for key, value in self.vca.data.model_configs.items():
                env_name = f'OSMLCM_VCA_MODEL_CONFIG_{key.upper().replace("-","_")}'
                environments[env_name] = value

        layer_config = {
            "summary": "lcm layer",
            "description": "pebble config layer for nbi",
            "services": {
                self.service_name: {
                    "override": "replace",
                    "summary": "lcm service",
                    "command": "python3 -m osm_lcm.lcm",
                    "startup": "enabled",
                    "user": "appuser",
                    "group": "appuser",
                    "environment": environments,
                }
            },
        }
        return layer_config

    def _get_mongodb_uri(self):
        return list(self.mongodb_client.fetch_relation_data().values())[0]["uris"]


if __name__ == "__main__":  # pragma: no cover
    main(OsmLcmCharm)
