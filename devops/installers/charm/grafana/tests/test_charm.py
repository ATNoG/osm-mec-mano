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
from unittest.mock import patch

from charm import GrafanaCharm
from ops.model import ActiveStatus, BlockedStatus
from ops.testing import Harness


class TestCharm(unittest.TestCase):
    """Prometheus Charm unit tests."""

    def setUp(self) -> NoReturn:
        """Test setup"""
        self.image_info = sys.modules["oci_image"].OCIImageResource().fetch()
        self.harness = Harness(GrafanaCharm)
        self.harness.set_leader(is_leader=True)
        self.harness.begin()
        self.config = {
            "max_file_size": 0,
            "ingress_whitelist_source_range": "",
            "tls_secret_name": "",
            "site_url": "https://grafana.192.168.100.100.nip.io",
            "cluster_issuer": "vault-issuer",
            "osm_dashboards": True,
        }
        self.harness.update_config(self.config)

    def test_config_changed(
        self,
    ) -> NoReturn:
        """Test ingress resources without HTTP."""

        self.harness.charm.on.config_changed.emit()

        # Assertions
        self.assertIsInstance(self.harness.charm.unit.status, BlockedStatus)
        self.assertTrue("prometheus" in self.harness.charm.unit.status.message)

    def test_config_changed_non_leader(
        self,
    ) -> NoReturn:
        """Test ingress resources without HTTP."""
        self.harness.set_leader(is_leader=False)
        self.harness.charm.on.config_changed.emit()

        # Assertions
        self.assertIsInstance(self.harness.charm.unit.status, ActiveStatus)

    @patch("opslib.osm.interfaces.grafana.GrafanaCluster.set_initial_password")
    def test_with_db_relation_and_prometheus(self, _) -> NoReturn:
        self.initialize_prometheus_relation()
        self.initialize_mysql_relation()
        self.assertIsInstance(self.harness.charm.unit.status, ActiveStatus)

    @patch("opslib.osm.interfaces.grafana.GrafanaCluster.set_initial_password")
    def test_with_db_config_and_prometheus(self, _) -> NoReturn:
        self.initialize_prometheus_relation()
        self.initialize_mysql_config()
        self.assertIsInstance(self.harness.charm.unit.status, ActiveStatus)

    def test_with_prometheus(
        self,
    ) -> NoReturn:
        """Test to see if prometheus relation is updated."""
        self.initialize_prometheus_relation()
        # Verifying status
        self.assertIsInstance(self.harness.charm.unit.status, BlockedStatus)

    def test_with_db_config(self) -> NoReturn:
        "Test with mysql config"
        self.initialize_mysql_config()
        # Verifying status
        self.assertIsInstance(self.harness.charm.unit.status, BlockedStatus)

    @patch("opslib.osm.interfaces.grafana.GrafanaCluster.set_initial_password")
    def test_with_db_relations(self, _) -> NoReturn:
        "Test with relations"
        self.initialize_mysql_relation()
        # Verifying status
        self.assertIsInstance(self.harness.charm.unit.status, BlockedStatus)

    def test_exception_db_relation_and_config(
        self,
    ) -> NoReturn:
        "Test with relations and config. Must throw exception"
        self.initialize_mysql_config()
        self.initialize_mysql_relation()
        # Verifying status
        self.assertIsInstance(self.harness.charm.unit.status, BlockedStatus)

    def initialize_prometheus_relation(self):
        relation_id = self.harness.add_relation("prometheus", "prometheus")
        self.harness.add_relation_unit(relation_id, "prometheus/0")
        self.harness.update_relation_data(
            relation_id,
            "prometheus",
            {"hostname": "prometheus", "port": 9090},
        )

    def initialize_mysql_config(self):
        self.harness.update_config(
            {"mysql_uri": "mysql://grafana:$grafanapw$@host:3606/db"}
        )

    def initialize_mysql_relation(self):
        relation_id = self.harness.add_relation("db", "mysql")
        self.harness.add_relation_unit(relation_id, "mysql/0")
        self.harness.update_relation_data(
            relation_id,
            "mysql/0",
            {
                "host": "mysql",
                "port": 3306,
                "user": "mano",
                "password": "manopw",
                "root_password": "rootmanopw",
            },
        )


if __name__ == "__main__":
    unittest.main()

# class TestCharm(unittest.TestCase):
#     """Grafana Charm unit tests."""

#     def setUp(self) -> NoReturn:
#         """Test setup"""
#         self.harness = Harness(GrafanaCharm)
#         self.harness.set_leader(is_leader=True)
#         self.harness.begin()

#     def test_on_start_without_relations(self) -> NoReturn:
#         """Test installation without any relation."""
#         self.harness.charm.on.start.emit()

#         # Verifying status
#         self.assertIsInstance(self.harness.charm.unit.status, BlockedStatus)

#         # Verifying status message
#         self.assertGreater(len(self.harness.charm.unit.status.message), 0)
#         self.assertTrue(
#             self.harness.charm.unit.status.message.startswith("Waiting for ")
#         )
#         self.assertIn("prometheus", self.harness.charm.unit.status.message)
#         self.assertTrue(self.harness.charm.unit.status.message.endswith(" relation"))

#     def test_on_start_with_relations_without_http(self) -> NoReturn:
#         """Test deployment."""
#         expected_result = {
#             "version": 3,
#             "containers": [
#                 {
#                     "name": "grafana",
#                     "imageDetails": self.harness.charm.image.fetch(),
#                     "imagePullPolicy": "Always",
#                     "ports": [
#                         {
#                             "name": "grafana",
#                             "containerPort": 3000,
#                             "protocol": "TCP",
#                         }
#                     ],
#                     "envConfig": {},
#                     "volumeConfig": [
#                         {
#                             "name": "dashboards",
#                             "mountPath": "/etc/grafana/provisioning/dashboards/",
#                             "files": [
#                                 {
#                                     "path": "dashboard-osm.yml",
#                                     "content": (
#                                         "apiVersion: 1\n"
#                                         "providers:\n"
#                                         "  - name: 'osm'\n"
#                                         "    orgId: 1\n"
#                                         "    folder: ''\n"
#                                         "    type: file\n"
#                                         "    options:\n"
#                                         "      path: /etc/grafana/provisioning/dashboards/\n"
#                                     ),
#                                 },
#                             ],
#                         },
#                         {
#                             "name": "datasources",
#                             "mountPath": "/etc/grafana/provisioning/datasources/",
#                             "files": [
#                                 {
#                                     "path": "datasource-prometheus.yml",
#                                     "content": (
#                                         "datasources:\n"
#                                         "  - access: proxy\n"
#                                         "    editable: true\n"
#                                         "    is_default: true\n"
#                                         "    name: osm_prometheus\n"
#                                         "    orgId: 1\n"
#                                         "    type: prometheus\n"
#                                         "    version: 1\n"
#                                         "    url: http://prometheus:9090\n"
#                                     ),
#                                 },
#                             ],
#                         },
#                     ],
#                     "kubernetes": {
#                         "readinessProbe": {
#                             "httpGet": {
#                                 "path": "/api/health",
#                                 "port": 3000,
#                             },
#                             "initialDelaySeconds": 10,
#                             "periodSeconds": 10,
#                             "timeoutSeconds": 5,
#                             "successThreshold": 1,
#                             "failureThreshold": 3,
#                         },
#                         "livenessProbe": {
#                             "httpGet": {
#                                 "path": "/api/health",
#                                 "port": 3000,
#                             },
#                             "initialDelaySeconds": 60,
#                             "timeoutSeconds": 30,
#                             "failureThreshold": 10,
#                         },
#                     },
#                 },
#             ],
#             "kubernetesResources": {"ingressResources": []},
#         }

#         self.harness.charm.on.start.emit()

#         # Initializing the prometheus relation
#         relation_id = self.harness.add_relation("prometheus", "prometheus")
#         self.harness.add_relation_unit(relation_id, "prometheus/0")
#         self.harness.update_relation_data(
#             relation_id,
#             "prometheus",
#             {
#                 "hostname": "prometheus",
#                 "port": "9090",
#             },
#         )

#         # Verifying status
#         self.assertNotIsInstance(self.harness.charm.unit.status, BlockedStatus)

#         pod_spec, _ = self.harness.get_pod_spec()

#         self.assertDictEqual(expected_result, pod_spec)

#     def test_ingress_resources_with_http(self) -> NoReturn:
#         """Test ingress resources with HTTP."""
#         expected_result = {
#             "version": 3,
#             "containers": [
#                 {
#                     "name": "grafana",
#                     "imageDetails": self.harness.charm.image.fetch(),
#                     "imagePullPolicy": "Always",
#                     "ports": [
#                         {
#                             "name": "grafana",
#                             "containerPort": 3000,
#                             "protocol": "TCP",
#                         }
#                     ],
#                     "envConfig": {},
#                     "volumeConfig": [
#                         {
#                             "name": "dashboards",
#                             "mountPath": "/etc/grafana/provisioning/dashboards/",
#                             "files": [
#                                 {
#                                     "path": "dashboard-osm.yml",
#                                     "content": (
#                                         "apiVersion: 1\n"
#                                         "providers:\n"
#                                         "  - name: 'osm'\n"
#                                         "    orgId: 1\n"
#                                         "    folder: ''\n"
#                                         "    type: file\n"
#                                         "    options:\n"
#                                         "      path: /etc/grafana/provisioning/dashboards/\n"
#                                     ),
#                                 },
#                             ],
#                         },
#                         {
#                             "name": "datasources",
#                             "mountPath": "/etc/grafana/provisioning/datasources/",
#                             "files": [
#                                 {
#                                     "path": "datasource-prometheus.yml",
#                                     "content": (
#                                         "datasources:\n"
#                                         "  - access: proxy\n"
#                                         "    editable: true\n"
#                                         "    is_default: true\n"
#                                         "    name: osm_prometheus\n"
#                                         "    orgId: 1\n"
#                                         "    type: prometheus\n"
#                                         "    version: 1\n"
#                                         "    url: http://prometheus:9090\n"
#                                     ),
#                                 },
#                             ],
#                         },
#                     ],
#                     "kubernetes": {
#                         "readinessProbe": {
#                             "httpGet": {
#                                 "path": "/api/health",
#                                 "port": 3000,
#                             },
#                             "initialDelaySeconds": 10,
#                             "periodSeconds": 10,
#                             "timeoutSeconds": 5,
#                             "successThreshold": 1,
#                             "failureThreshold": 3,
#                         },
#                         "livenessProbe": {
#                             "httpGet": {
#                                 "path": "/api/health",
#                                 "port": 3000,
#                             },
#                             "initialDelaySeconds": 60,
#                             "timeoutSeconds": 30,
#                             "failureThreshold": 10,
#                         },
#                     },
#                 },
#             ],
#             "kubernetesResources": {
#                 "ingressResources": [
#                     {
#                         "name": "grafana-ingress",
#                         "annotations": {
#                             "nginx.ingress.kubernetes.io/proxy-body-size": "0",
#                             "nginx.ingress.kubernetes.io/ssl-redirect": "false",
#                         },
#                         "spec": {
#                             "rules": [
#                                 {
#                                     "host": "grafana",
#                                     "http": {
#                                         "paths": [
#                                             {
#                                                 "path": "/",
#                                                 "backend": {
#                                                     "serviceName": "grafana",
#                                                     "servicePort": 3000,
#                                                 },
#                                             }
#                                         ]
#                                     },
#                                 }
#                             ]
#                         },
#                     }
#                 ],
#             },
#         }

#         self.harness.charm.on.start.emit()

#         # Initializing the prometheus relation
#         relation_id = self.harness.add_relation("prometheus", "prometheus")
#         self.harness.add_relation_unit(relation_id, "prometheus/0")
#         self.harness.update_relation_data(
#             relation_id,
#             "prometheus",
#             {
#                 "hostname": "prometheus",
#                 "port": "9090",
#             },
#         )

#         self.harness.update_config({"site_url": "http://grafana"})

#         pod_spec, _ = self.harness.get_pod_spec()

#         self.assertDictEqual(expected_result, pod_spec)

#     def test_ingress_resources_with_https(self) -> NoReturn:
#         """Test ingress resources with HTTPS."""
#         expected_result = {
#             "version": 3,
#             "containers": [
#                 {
#                     "name": "grafana",
#                     "imageDetails": self.harness.charm.image.fetch(),
#                     "imagePullPolicy": "Always",
#                     "ports": [
#                         {
#                             "name": "grafana",
#                             "containerPort": 3000,
#                             "protocol": "TCP",
#                         }
#                     ],
#                     "envConfig": {},
#                     "volumeConfig": [
#                         {
#                             "name": "dashboards",
#                             "mountPath": "/etc/grafana/provisioning/dashboards/",
#                             "files": [
#                                 {
#                                     "path": "dashboard-osm.yml",
#                                     "content": (
#                                         "apiVersion: 1\n"
#                                         "providers:\n"
#                                         "  - name: 'osm'\n"
#                                         "    orgId: 1\n"
#                                         "    folder: ''\n"
#                                         "    type: file\n"
#                                         "    options:\n"
#                                         "      path: /etc/grafana/provisioning/dashboards/\n"
#                                     ),
#                                 },
#                             ],
#                         },
#                         {
#                             "name": "datasources",
#                             "mountPath": "/etc/grafana/provisioning/datasources/",
#                             "files": [
#                                 {
#                                     "path": "datasource-prometheus.yml",
#                                     "content": (
#                                         "datasources:\n"
#                                         "  - access: proxy\n"
#                                         "    editable: true\n"
#                                         "    is_default: true\n"
#                                         "    name: osm_prometheus\n"
#                                         "    orgId: 1\n"
#                                         "    type: prometheus\n"
#                                         "    version: 1\n"
#                                         "    url: http://prometheus:9090\n"
#                                     ),
#                                 },
#                             ],
#                         },
#                     ],
#                     "kubernetes": {
#                         "readinessProbe": {
#                             "httpGet": {
#                                 "path": "/api/health",
#                                 "port": 3000,
#                             },
#                             "initialDelaySeconds": 10,
#                             "periodSeconds": 10,
#                             "timeoutSeconds": 5,
#                             "successThreshold": 1,
#                             "failureThreshold": 3,
#                         },
#                         "livenessProbe": {
#                             "httpGet": {
#                                 "path": "/api/health",
#                                 "port": 3000,
#                             },
#                             "initialDelaySeconds": 60,
#                             "timeoutSeconds": 30,
#                             "failureThreshold": 10,
#                         },
#                     },
#                 },
#             ],
#             "kubernetesResources": {
#                 "ingressResources": [
#                     {
#                         "name": "grafana-ingress",
#                         "annotations": {
#                             "nginx.ingress.kubernetes.io/proxy-body-size": "0",
#                         },
#                         "spec": {
#                             "rules": [
#                                 {
#                                     "host": "grafana",
#                                     "http": {
#                                         "paths": [
#                                             {
#                                                 "path": "/",
#                                                 "backend": {
#                                                     "serviceName": "grafana",
#                                                     "servicePort": 3000,
#                                                 },
#                                             }
#                                         ]
#                                     },
#                                 }
#                             ],
#                             "tls": [{"hosts": ["grafana"], "secretName": "grafana"}],
#                         },
#                     }
#                 ],
#             },
#         }

#         self.harness.charm.on.start.emit()

#         # Initializing the prometheus relation
#         relation_id = self.harness.add_relation("prometheus", "prometheus")
#         self.harness.add_relation_unit(relation_id, "prometheus/0")
#         self.harness.update_relation_data(
#             relation_id,
#             "prometheus",
#             {
#                 "hostname": "prometheus",
#                 "port": "9090",
#             },
#         )

#         self.harness.update_config(
#             {"site_url": "https://grafana", "tls_secret_name": "grafana"}
#         )

#         pod_spec, _ = self.harness.get_pod_spec()

#         self.assertDictEqual(expected_result, pod_spec)

#     def test_ingress_resources_with_https_and_ingress_whitelist(self) -> NoReturn:
#         """Test ingress resources with HTTPS and ingress whitelist."""
#         expected_result = {
#             "version": 3,
#             "containers": [
#                 {
#                     "name": "grafana",
#                     "imageDetails": self.harness.charm.image.fetch(),
#                     "imagePullPolicy": "Always",
#                     "ports": [
#                         {
#                             "name": "grafana",
#                             "containerPort": 3000,
#                             "protocol": "TCP",
#                         }
#                     ],
#                     "envConfig": {},
#                     "volumeConfig": [
#                         {
#                             "name": "dashboards",
#                             "mountPath": "/etc/grafana/provisioning/dashboards/",
#                             "files": [
#                                 {
#                                     "path": "dashboard-osm.yml",
#                                     "content": (
#                                         "apiVersion: 1\n"
#                                         "providers:\n"
#                                         "  - name: 'osm'\n"
#                                         "    orgId: 1\n"
#                                         "    folder: ''\n"
#                                         "    type: file\n"
#                                         "    options:\n"
#                                         "      path: /etc/grafana/provisioning/dashboards/\n"
#                                     ),
#                                 },
#                             ],
#                         },
#                         {
#                             "name": "datasources",
#                             "mountPath": "/etc/grafana/provisioning/datasources/",
#                             "files": [
#                                 {
#                                     "path": "datasource-prometheus.yml",
#                                     "content": (
#                                         "datasources:\n"
#                                         "  - access: proxy\n"
#                                         "    editable: true\n"
#                                         "    is_default: true\n"
#                                         "    name: osm_prometheus\n"
#                                         "    orgId: 1\n"
#                                         "    type: prometheus\n"
#                                         "    version: 1\n"
#                                         "    url: http://prometheus:9090\n"
#                                     ),
#                                 },
#                             ],
#                         },
#                     ],
#                     "kubernetes": {
#                         "readinessProbe": {
#                             "httpGet": {
#                                 "path": "/api/health",
#                                 "port": 3000,
#                             },
#                             "initialDelaySeconds": 10,
#                             "periodSeconds": 10,
#                             "timeoutSeconds": 5,
#                             "successThreshold": 1,
#                             "failureThreshold": 3,
#                         },
#                         "livenessProbe": {
#                             "httpGet": {
#                                 "path": "/api/health",
#                                 "port": 3000,
#                             },
#                             "initialDelaySeconds": 60,
#                             "timeoutSeconds": 30,
#                             "failureThreshold": 10,
#                         },
#                     },
#                 },
#             ],
#             "kubernetesResources": {
#                 "ingressResources": [
#                     {
#                         "name": "grafana-ingress",
#                         "annotations": {
#                             "nginx.ingress.kubernetes.io/proxy-body-size": "0",
#                             "nginx.ingress.kubernetes.io/whitelist-source-range": "0.0.0.0/0",
#                         },
#                         "spec": {
#                             "rules": [
#                                 {
#                                     "host": "grafana",
#                                     "http": {
#                                         "paths": [
#                                             {
#                                                 "path": "/",
#                                                 "backend": {
#                                                     "serviceName": "grafana",
#                                                     "servicePort": 3000,
#                                                 },
#                                             }
#                                         ]
#                                     },
#                                 }
#                             ],
#                             "tls": [{"hosts": ["grafana"], "secretName": "grafana"}],
#                         },
#                     }
#                 ],
#             },
#         }

#         self.harness.charm.on.start.emit()

#         # Initializing the prometheus relation
#         relation_id = self.harness.add_relation("prometheus", "prometheus")
#         self.harness.add_relation_unit(relation_id, "prometheus/0")
#         self.harness.update_relation_data(
#             relation_id,
#             "prometheus",
#             {
#                 "hostname": "prometheus",
#                 "port": "9090",
#             },
#         )

#         self.harness.update_config(
#             {
#                 "site_url": "https://grafana",
#                 "tls_secret_name": "grafana",
#                 "ingress_whitelist_source_range": "0.0.0.0/0",
#             }
#         )

#         pod_spec, _ = self.harness.get_pod_spec()

#         self.assertDictEqual(expected_result, pod_spec)

#     def test_on_prometheus_unit_relation_changed(self) -> NoReturn:
#         """Test to see if prometheus relation is updated."""
#         self.harness.charm.on.start.emit()

#         relation_id = self.harness.add_relation("prometheus", "prometheus")
#         self.harness.add_relation_unit(relation_id, "prometheus/0")
#         self.harness.update_relation_data(
#             relation_id,
#             "prometheus",
#             {"hostname": "prometheus", "port": 9090},
#         )

#         # Verifying status
#         self.assertNotIsInstance(self.harness.charm.unit.status, BlockedStatus)


if __name__ == "__main__":
    unittest.main()
