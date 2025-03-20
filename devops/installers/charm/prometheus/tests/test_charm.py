#!/usr/bin/env python3
# Copyright 2020 Canonical Ltd.
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

import sys
from typing import NoReturn
import unittest

from charm import PrometheusCharm
from ops.model import ActiveStatus
from ops.testing import Harness


class TestCharm(unittest.TestCase):
    """Prometheus Charm unit tests."""

    def setUp(self) -> NoReturn:
        """Test setup"""
        self.image_info = sys.modules["oci_image"].OCIImageResource().fetch()
        self.harness = Harness(PrometheusCharm)
        self.harness.set_leader(is_leader=True)
        self.harness.begin()
        self.config = {
            "web-subpath": "/",
            "default-target": "",
            "max_file_size": 0,
            "ingress_whitelist_source_range": "",
            "tls_secret_name": "",
            "site_url": "https://prometheus.192.168.100.100.nip.io",
            "cluster_issuer": "vault-issuer",
            "enable_web_admin_api": False,
            "web_config_username": "admin",
            "web_config_password": "1234",
        }
        self.harness.update_config(self.config)

    def test_config_changed(
        self,
    ) -> NoReturn:
        """Test ingress resources without HTTP."""

        self.harness.charm.on.config_changed.emit()

        # Assertions
        self.assertIsInstance(self.harness.charm.unit.status, ActiveStatus)

    def test_config_changed_non_leader(
        self,
    ) -> NoReturn:
        """Test ingress resources without HTTP."""
        self.harness.set_leader(is_leader=False)
        self.harness.charm.on.config_changed.emit()

        # Assertions
        self.assertIsInstance(self.harness.charm.unit.status, ActiveStatus)

    def test_publish_prometheus_info(
        self,
    ) -> NoReturn:
        """Test to see if prometheus relation is updated."""
        expected_result = {
            "hostname": self.harness.charm.app.name,
            "port": "9090",
            "user": "admin",
            "password": "1234",
        }

        relation_id = self.harness.add_relation("prometheus", "mon")
        self.harness.add_relation_unit(relation_id, "mon/0")
        relation_data = self.harness.get_relation_data(
            relation_id, self.harness.charm.app.name
        )

        self.assertDictEqual(expected_result, relation_data)

    def test_publish_prometheus_info_non_leader(
        self,
    ) -> NoReturn:
        """Test to see if prometheus relation is updated."""
        expected_result = {}

        self.harness.set_leader(is_leader=False)
        relation_id = self.harness.add_relation("prometheus", "mon")
        self.harness.add_relation_unit(relation_id, "mon/0")
        relation_data = self.harness.get_relation_data(
            relation_id, self.harness.charm.app.name
        )

        self.assertDictEqual(expected_result, relation_data)


if __name__ == "__main__":
    unittest.main()
