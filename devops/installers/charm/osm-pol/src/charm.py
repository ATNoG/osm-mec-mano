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

"""OSM POL charm.

See more: https://charmhub.io/osm
"""

import logging
from typing import Any, Dict

from charms.data_platform_libs.v0.data_interfaces import DatabaseRequires
from charms.kafka_k8s.v0.kafka import KafkaEvents, KafkaRequires
from charms.osm_libs.v0.utils import (
    CharmError,
    DebugMode,
    HostPath,
    check_container_ready,
    check_service_active,
)
from ops.charm import ActionEvent, CharmBase
from ops.framework import StoredState
from ops.main import main
from ops.model import ActiveStatus, Container

from legacy_interfaces import MysqlClient

HOSTPATHS = [
    HostPath(
        config="pol-hostpath",
        container_path="/usr/lib/python3/dist-packages/osm_policy_module",
    ),
    HostPath(
        config="common-hostpath",
        container_path="/usr/lib/python3/dist-packages/osm_common",
    ),
]

logger = logging.getLogger(__name__)


class OsmPolCharm(CharmBase):
    """OSM POL Kubernetes sidecar charm."""

    on = KafkaEvents()
    _stored = StoredState()
    container_name = "pol"
    service_name = "pol"

    def __init__(self, *args):
        super().__init__(*args)

        self.kafka = KafkaRequires(self)
        self.mongodb_client = DatabaseRequires(self, "mongodb", database_name="osm")
        self.mysql_client = MysqlClient(self, "mysql")
        self._observe_charm_events()
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
        """Handler for the kafka-broken event."""
        # Check Pebble has started in the container
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
            event.fail("debug-mode has not started. Hint: juju config pol debug-mode=true")
            return

        debug_info = {"command": self.debug_mode.command, "password": self.debug_mode.password}
        event.set_results(debug_info)

    # ---------------------------------------------------------------------------
    #   Validation and configuration and more
    # ---------------------------------------------------------------------------

    def _observe_charm_events(self) -> None:
        event_handler_mapping = {
            # Core lifecycle events
            self.on.pol_pebble_ready: self._on_config_changed,
            self.on.config_changed: self._on_config_changed,
            self.on.update_status: self._on_update_status,
            # Relation events
            self.on.kafka_available: self._on_config_changed,
            self.on["kafka"].relation_broken: self._on_required_relation_broken,
            self.on["mysql"].relation_changed: self._on_config_changed,
            self.on["mysql"].relation_broken: self._on_config_changed,
            self.mongodb_client.on.database_created: self._on_config_changed,
            self.on["mongodb"].relation_broken: self._on_required_relation_broken,
            # Action events
            self.on.get_debug_mode_information_action: self._on_get_debug_mode_information_action,
        }

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
        if not self.config.get("mysql-uri") and self.mysql_client.is_missing_data_in_unit():
            missing_relations.append("mysql")

        if missing_relations:
            relations_str = ", ".join(missing_relations)
            one_relation_missing = len(missing_relations) == 1
            error_msg = f'need {relations_str} relation{"" if one_relation_missing else "s"}'
            logger.warning(error_msg)
            raise CharmError(error_msg)

    def _configure_service(self, container: Container) -> None:
        """Add Pebble layer with the pol service."""
        logger.debug(f"configuring {self.app.name} service")
        container.add_layer("pol", self._get_layer(), combine=True)
        container.replan()

    def _get_layer(self) -> Dict[str, Any]:
        """Get layer for Pebble."""
        return {
            "summary": "pol layer",
            "description": "pebble config layer for pol",
            "services": {
                self.service_name: {
                    "override": "replace",
                    "summary": "pol service",
                    "command": "/bin/bash scripts/start.sh",
                    "startup": "enabled",
                    "user": "appuser",
                    "group": "appuser",
                    "environment": {
                        # General configuration
                        "OSMPOL_GLOBAL_LOGLEVEL": self.config["log-level"],
                        # Kafka configuration
                        "OSMPOL_MESSAGE_HOST": self.kafka.host,
                        "OSMPOL_MESSAGE_PORT": self.kafka.port,
                        "OSMPOL_MESSAGE_DRIVER": "kafka",
                        # Database Mongodb configuration
                        "OSMPOL_DATABASE_DRIVER": "mongo",
                        "OSMPOL_DATABASE_URI": self._get_mongodb_uri(),
                        # Database MySQL configuration
                        "OSMPOL_SQL_DATABASE_URI": self._get_mysql_uri(),
                    },
                }
            },
        }

    def _get_mysql_uri(self):
        return self.config.get("mysql-uri") or self.mysql_client.get_root_uri("pol")

    def _get_mongodb_uri(self):
        return list(self.mongodb_client.fetch_relation_data().values())[0]["uris"]


if __name__ == "__main__":  # pragma: no cover
    main(OsmPolCharm)
