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

"""OSM NG-UI charm.

See more: https://charmhub.io/osm
"""

import logging
import re
from typing import Any, Dict

from charms.nginx_ingress_integrator.v0.ingress import IngressRequires
from charms.observability_libs.v1.kubernetes_service_patch import KubernetesServicePatch
from charms.osm_libs.v0.utils import (
    CharmError,
    check_container_ready,
    check_service_active,
)
from charms.osm_nbi.v0.nbi import NbiRequires
from lightkube.models.core_v1 import ServicePort
from ops.charm import CharmBase
from ops.framework import StoredState
from ops.main import main
from ops.model import ActiveStatus, BlockedStatus, Container

SERVICE_PORT = 80

logger = logging.getLogger(__name__)


class OsmNgUiCharm(CharmBase):
    """OSM NG-UI Kubernetes sidecar charm."""

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
        self._observe_charm_events()
        self._patch_k8s_service()
        self._stored.set_default(default_site_patched=False)
        self.nbi = NbiRequires(self)
        self.container: Container = self.unit.get_container("ng-ui")

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

            self._configure_service(self.container)
            self._update_ingress_config()
            # Update charm status
            self._on_update_status()
        except CharmError as e:
            logger.debug(e.message)
            self.unit.status = e.status

    def _on_update_status(self, _=None) -> None:
        """Handler for the update-status event."""
        try:
            self._check_relations()
            check_container_ready(self.container)
            check_service_active(self.container, "ng-ui")
            self.unit.status = ActiveStatus()
        except CharmError as e:
            logger.debug(e.message)
            self.unit.status = e.status

    def _on_nbi_relation_broken(self, _) -> None:
        """Handler for the nbi relation broken event."""
        # Check Pebble has started in the container
        try:
            check_container_ready(self.container)
            check_service_active(self.container, "ng-ui")
            self.container.stop("ng-ui")
            self._stored.default_site_patched = False
        except CharmError:
            pass
        finally:
            self.unit.status = BlockedStatus("need nbi relation")

    # ---------------------------------------------------------------------------
    #   Validation and configuration and more
    # ---------------------------------------------------------------------------

    def _patch_k8s_service(self) -> None:
        port = ServicePort(SERVICE_PORT, name=f"{self.app.name}")
        self.service_patcher = KubernetesServicePatch(self, [port])

    def _observe_charm_events(self) -> None:
        event_handler_mapping = {
            # Core lifecycle events
            self.on.ng_ui_pebble_ready: self._on_config_changed,
            self.on.config_changed: self._on_config_changed,
            self.on.update_status: self._on_update_status,
            # Relation events
            self.on["nbi"].relation_changed: self._on_config_changed,
            self.on["nbi"].relation_broken: self._on_nbi_relation_broken,
        }
        for event, handler in event_handler_mapping.items():
            self.framework.observe(event, handler)

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

        if not self.nbi.host or not self.nbi.port:
            raise CharmError("need nbi relation")

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
        """Add Pebble layer with the ng-ui service."""
        logger.debug(f"configuring {self.app.name} service")
        self._patch_default_site(container)
        container.add_layer("ng-ui", self._get_layer(), combine=True)
        container.replan()

    def _get_layer(self) -> Dict[str, Any]:
        """Get layer for Pebble."""
        return {
            "summary": "ng-ui layer",
            "description": "pebble config layer for ng-ui",
            "services": {
                "ng-ui": {
                    "override": "replace",
                    "summary": "ng-ui service",
                    "command": 'nginx -g "daemon off;"',
                    "startup": "enabled",
                }
            },
        }

    def _patch_default_site(self, container: Container) -> None:
        max_body_size = self.config.get("max-body-size")
        if (
            self._stored.default_site_patched
            and max_body_size == self._stored.default_site_max_body_size
        ):
            return
        default_site_config = container.pull("/etc/nginx/sites-available/default").read()
        default_site_config = re.sub(
            "client_max_body_size .*\n",
            f"client_max_body_size {max_body_size}M;\n",
            default_site_config,
        )
        default_site_config = re.sub(
            "proxy_pass .*\n",
            f"proxy_pass http://{self.nbi.host}:{self.nbi.port};\n",
            default_site_config,
        )
        container.push("/etc/nginx/sites-available/default", default_site_config)
        self._stored.default_site_patched = True
        self._stored.default_site_max_body_size = max_body_size


if __name__ == "__main__":  # pragma: no cover
    main(OsmNgUiCharm)
