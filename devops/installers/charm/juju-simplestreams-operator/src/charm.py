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

"""Juju simpletreams charm."""

import logging
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict

from charms.nginx_ingress_integrator.v0.ingress import IngressRequires
from charms.observability_libs.v1.kubernetes_service_patch import KubernetesServicePatch
from charms.osm_libs.v0.utils import (
    CharmError,
    check_container_ready,
    check_service_active,
)
from lightkube.models.core_v1 import ServicePort
from ops.charm import ActionEvent, CharmBase
from ops.main import main
from ops.model import ActiveStatus, Container

SERVICE_PORT = 8080

logger = logging.getLogger(__name__)
container_name = "server"


@dataclass
class ImageMetadata:
    """Image Metadata."""

    region: str
    auth_url: str
    image_id: str
    series: str


class JujuSimplestreamsCharm(CharmBase):
    """Simplestreams Kubernetes sidecar charm."""

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
        event_handler_mapping = {
            # Core lifecycle events
            self.on["server"].pebble_ready: self._on_server_pebble_ready,
            self.on.update_status: self._on_update_status,
            self.on["peer"].relation_changed: self._push_image_metadata_from_relation,
            # Action events
            self.on["add-image-metadata"].action: self._on_add_image_metadata_action,
        }

        for event, handler in event_handler_mapping.items():
            self.framework.observe(event, handler)

        port = ServicePort(SERVICE_PORT, name=f"{self.app.name}")
        self.service_patcher = KubernetesServicePatch(self, [port])
        self.container: Container = self.unit.get_container(container_name)
        self.unit.set_workload_version(self.unit.name)

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

    def _on_server_pebble_ready(self, _) -> None:
        """Handler for the config-changed event."""
        try:
            self._push_configuration()
            self._configure_service()
            self._push_image_metadata_from_relation()
            # Update charm status
            self._on_update_status()
        except CharmError as e:
            logger.debug(e.message)
            self.unit.status = e.status

    def _on_update_status(self, _=None) -> None:
        """Handler for the update-status event."""
        try:
            check_container_ready(self.container)
            check_service_active(self.container, container_name)
            self.unit.status = ActiveStatus()
        except CharmError as e:
            logger.debug(e.message)
            self.unit.status = e.status

    def _push_image_metadata_from_relation(self, _=None):
        subprocess.run(["rm", "-rf", "/tmp/simplestreams"])
        subprocess.run(["mkdir", "-p", "/tmp/simplestreams"])
        image_metadata_dict = self._get_image_metadata_from_relation()
        for image_metadata in image_metadata_dict.values():
            subprocess.run(
                [
                    "files/juju-metadata",
                    "generate-image",
                    "-d",
                    "/tmp/simplestreams",
                    "-i",
                    image_metadata.image_id,
                    "-s",
                    image_metadata.series,
                    "-r",
                    image_metadata.region,
                    "-u",
                    image_metadata.auth_url,
                ]
            )
        subprocess.run(["chmod", "555", "-R", "/tmp/simplestreams"])
        self.container.push_path("/tmp/simplestreams", "/app/static")

    def _on_add_image_metadata_action(self, event: ActionEvent):
        relation = self.model.get_relation("peer")
        try:
            if not relation:
                raise Exception("charm has not been fully initialized. Try again later.")
            if not self.unit.is_leader():
                raise Exception("I am not the leader!")
            if any(
                prohibited_char in param_value
                for prohibited_char in ",; "
                for param_value in event.params.values()
            ):
                event.fail("invalid params")
                return

            image_metadata_dict = self._get_image_metadata_from_relation()

            new_image_metadata = ImageMetadata(
                region=event.params["region"],
                auth_url=event.params["auth-url"],
                image_id=event.params["image-id"],
                series=event.params["series"],
            )

            image_metadata_dict[event.params["image-id"]] = new_image_metadata

            new_relation_data = []
            for image_metadata in image_metadata_dict.values():
                new_relation_data.append(
                    f"{image_metadata.image_id};{image_metadata.series};{image_metadata.region};{image_metadata.auth_url}"
                )
            relation.data[self.app]["data"] = ",".join(new_relation_data)
        except Exception as e:
            event.fail(f"Action failed: {e}")
            logger.error(f"Action failed: {e}")

    # ---------------------------------------------------------------------------
    #   Validation and configuration and more
    # ---------------------------------------------------------------------------

    def _get_image_metadata_from_relation(self) -> Dict[str, ImageMetadata]:
        if not (relation := self.model.get_relation("peer")):
            return {}

        image_metadata_dict: Dict[str, ImageMetadata] = {}

        relation_data = relation.data[self.app].get("data", "")
        if relation_data:
            for image_metadata_string in relation_data.split(","):
                image_id, series, region, auth_url = image_metadata_string.split(";")
                image_metadata_dict[image_id] = ImageMetadata(
                    region=region,
                    auth_url=auth_url,
                    image_id=image_id,
                    series=series,
                )

        return image_metadata_dict

    def _configure_service(self) -> None:
        """Add Pebble layer with the ro service."""
        logger.debug(f"configuring {self.app.name} service")
        self.container.add_layer(container_name, self._get_layer(), combine=True)
        self.container.replan()

    def _push_configuration(self) -> None:
        """Push nginx configuration to the container."""
        self.container.push("/etc/nginx/nginx.conf", Path("files/nginx.conf").read_text())
        self.container.make_dir("/app/static", make_parents=True)

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

    def _get_layer(self) -> Dict[str, Any]:
        """Get layer for Pebble."""
        return {
            "summary": "server layer",
            "description": "pebble config layer for server",
            "services": {
                container_name: {
                    "override": "replace",
                    "summary": "server service",
                    "command": 'nginx -g "daemon off;"',
                    "startup": "enabled",
                }
            },
        }


if __name__ == "__main__":  # pragma: no cover
    main(JujuSimplestreamsCharm)
