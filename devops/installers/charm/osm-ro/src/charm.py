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

"""OSM RO charm.

See more: https://charmhub.io/osm
"""

import base64
import logging
from typing import Any, Dict

from charms.data_platform_libs.v0.data_interfaces import DatabaseRequires
from charms.kafka_k8s.v0.kafka import KafkaEvents, KafkaRequires
from charms.observability_libs.v1.kubernetes_service_patch import KubernetesServicePatch
from charms.osm_libs.v0.utils import (
    CharmError,
    DebugMode,
    HostPath,
    check_container_ready,
    check_service_active,
)
from charms.osm_ro.v0.ro import RoProvides
from lightkube.models.core_v1 import ServicePort
from ops.charm import ActionEvent, CharmBase, RelationJoinedEvent
from ops.framework import StoredState
from ops.main import main
from ops.model import ActiveStatus, Container

ro_host_paths = {
    "NG-RO": "/usr/lib/python3/dist-packages/osm_ng_ro",
    "RO-plugin": "/usr/lib/python3/dist-packages/osm_ro_plugin",
    "RO-SDN-arista_cloudvision": "/usr/lib/python3/dist-packages/osm_rosdn_arista_cloudvision",
    "RO-SDN-dpb": "/usr/lib/python3/dist-packages/osm_rosdn_dpb",
    "RO-SDN-dynpac": "/usr/lib/python3/dist-packages/osm_rosdn_dynpac",
    "RO-SDN-floodlight_openflow": "/usr/lib/python3/dist-packages/osm_rosdn_floodlightof",
    "RO-SDN-ietfl2vpn": "/usr/lib/python3/dist-packages/osm_rosdn_ietfl2vpn",
    "RO-SDN-juniper_contrail": "/usr/lib/python3/dist-packages/osm_rosdn_juniper_contrail",
    "RO-SDN-odl_openflow": "/usr/lib/python3/dist-packages/osm_rosdn_odlof",
    "RO-SDN-onos_openflow": "/usr/lib/python3/dist-packages/osm_rosdn_onosof",
    "RO-SDN-onos_vpls": "/usr/lib/python3/dist-packages/osm_rosdn_onos_vpls",
    "RO-VIM-aws": "/usr/lib/python3/dist-packages/osm_rovim_aws",
    "RO-VIM-azure": "/usr/lib/python3/dist-packages/osm_rovim_azure",
    "RO-VIM-gcp": "/usr/lib/python3/dist-packages/osm_rovim_gcp",
    "RO-VIM-openstack": "/usr/lib/python3/dist-packages/osm_rovim_openstack",
    "RO-VIM-openvim": "/usr/lib/python3/dist-packages/osm_rovim_openvim",
    "RO-VIM-vmware": "/usr/lib/python3/dist-packages/osm_rovim_vmware",
}
HOSTPATHS = [
    HostPath(
        config="ro-hostpath",
        container_path="/usr/lib/python3/dist-packages/",
        submodules=ro_host_paths,
    ),
    HostPath(
        config="common-hostpath",
        container_path="/usr/lib/python3/dist-packages/osm_common",
    ),
]
SERVICE_PORT = 9090
USER = GROUP = "appuser"

logger = logging.getLogger(__name__)


def decode(content: str):
    """Base64 decoding of a string."""
    return base64.b64decode(content.encode("utf-8")).decode("utf-8")


class OsmRoCharm(CharmBase):
    """OSM RO Kubernetes sidecar charm."""

    on = KafkaEvents()
    service_name = "ro"
    _stored = StoredState()

    def __init__(self, *args):
        super().__init__(*args)
        self._stored.set_default(certificates=set())
        self.kafka = KafkaRequires(self)
        self.mongodb_client = DatabaseRequires(self, "mongodb", database_name="osm")
        self._observe_charm_events()
        self._patch_k8s_service()
        self.ro = RoProvides(self)
        self.container: Container = self.unit.get_container("ro")
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

            self._configure_certificates()
            if not self.debug_mode.started:
                self._configure_service()
            self._update_ro_relation()

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
            check_service_active(self.container, "ro")
            self.container.stop("ro")
        except CharmError:
            pass

        self._on_update_status()

    def _update_ro_relation(self, event: RelationJoinedEvent = None) -> None:
        """Handler for the ro-relation-joined event."""
        try:
            if self.unit.is_leader():
                check_container_ready(self.container)
                check_service_active(self.container, "ro")
                self.ro.set_host_info(
                    self.app.name, SERVICE_PORT, event.relation if event else None
                )
        except CharmError as e:
            self.unit.status = e.status

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
    #   Validation and configuration and more
    # ---------------------------------------------------------------------------

    def _patch_k8s_service(self) -> None:
        port = ServicePort(SERVICE_PORT, name=f"{self.app.name}")
        self.service_patcher = KubernetesServicePatch(self, [port])

    def _observe_charm_events(self) -> None:
        event_handler_mapping = {
            # Core lifecycle events
            self.on.ro_pebble_ready: self._on_config_changed,
            self.on.config_changed: self._on_config_changed,
            self.on.update_status: self._on_update_status,
            # Relation events
            self.on.kafka_available: self._on_config_changed,
            self.on["kafka"].relation_broken: self._on_required_relation_broken,
            self.mongodb_client.on.database_created: self._on_config_changed,
            self.on["mongodb"].relation_broken: self._on_required_relation_broken,
            self.on.ro_relation_joined: self._update_ro_relation,
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
        if self.config["log-level"].upper() not in [
            "TRACE",
            "DEBUG",
            "INFO",
            "WARN",
            "ERROR",
            "FATAL",
        ]:
            raise CharmError("invalid value for log-level option")

        refresh_period = self.config.get("period_refresh_active")
        if refresh_period and refresh_period < 60 and refresh_period != -1:
            raise ValueError(
                "Refresh Period is too tight, insert >= 60 seconds or disable using -1"
            )

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

        if missing_relations:
            relations_str = ", ".join(missing_relations)
            one_relation_missing = len(missing_relations) == 1
            error_msg = f'need {relations_str} relation{"" if one_relation_missing else "s"}'
            logger.warning(error_msg)
            raise CharmError(error_msg)

    def _configure_certificates(self) -> None:
        """Push certificates to the RO container."""
        if not (certificate_config := self.config.get("certificates")):
            return

        certificates_list = certificate_config.split(",")
        updated_certificates = set()

        for certificate in certificates_list:
            if ":" not in certificate:
                continue
            name, content = certificate.split(":")
            content = decode(content)
            self.container.push(
                f"/certs/{name}",
                content,
                permissions=0o400,
                make_dirs=True,
                user=USER,
                group=GROUP,
            )
            updated_certificates.add(name)
            self._stored.certificates.add(name)
            logger.info(f"certificate {name} pushed successfully")

        stored_certificates = {c for c in self._stored.certificates}
        for certificate_to_remove in stored_certificates.difference(updated_certificates):
            self.container.remove_path(f"/certs/{certificate_to_remove}")
            self._stored.certificates.remove(certificate_to_remove)
            logger.info(f"certificate {certificate_to_remove} removed successfully")

    def _configure_service(self) -> None:
        """Add Pebble layer with the ro service."""
        logger.debug(f"configuring {self.app.name} service")
        self.container.add_layer("ro", self._get_layer(), combine=True)
        self.container.replan()

    def _get_layer(self) -> Dict[str, Any]:
        """Get layer for Pebble."""
        return {
            "summary": "ro layer",
            "description": "pebble config layer for ro",
            "services": {
                "ro": {
                    "override": "replace",
                    "summary": "ro service",
                    "command": "/bin/sh -c 'cd /app/osm_ro && python3 -u -m osm_ng_ro.ro_main'",  # cd /app/osm_nbi is needed until we upgrade Juju to 3.x.
                    "startup": "enabled",
                    "user": USER,
                    "group": GROUP,
                    "working-dir": "/app/osm_ro",  # This parameter has no effect in Juju 2.9.x.
                    "environment": {
                        # General configuration
                        "OSMRO_LOG_LEVEL": self.config["log-level"].upper(),
                        # Kafka configuration
                        "OSMRO_MESSAGE_HOST": self.kafka.host,
                        "OSMRO_MESSAGE_PORT": self.kafka.port,
                        "OSMRO_MESSAGE_DRIVER": "kafka",
                        # Database configuration
                        "OSMRO_DATABASE_DRIVER": "mongo",
                        "OSMRO_DATABASE_URI": self._get_mongodb_uri(),
                        "OSMRO_DATABASE_COMMONKEY": self.config["database-commonkey"],
                        # Storage configuration
                        "OSMRO_STORAGE_DRIVER": "mongo",
                        "OSMRO_STORAGE_PATH": "/app/storage",
                        "OSMRO_STORAGE_COLLECTION": "files",
                        "OSMRO_STORAGE_URI": self._get_mongodb_uri(),
                        "OSMRO_PERIOD_REFRESH_ACTIVE": self.config.get("period_refresh_active")
                        or 60,
                    },
                }
            },
        }

    def _get_mongodb_uri(self):
        return list(self.mongodb_client.fetch_relation_data().values())[0]["uris"]


if __name__ == "__main__":  # pragma: no cover
    main(OsmRoCharm)
