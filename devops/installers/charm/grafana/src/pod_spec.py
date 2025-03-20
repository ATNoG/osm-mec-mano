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

import logging
from ipaddress import ip_network
from typing import Any, Dict, List
from urllib.parse import urlparse
from pathlib import Path
from string import Template

logger = logging.getLogger(__name__)


def _validate_max_file_size(max_file_size: int, site_url: str) -> bool:
    """Validate max_file_size.

    Args:
        max_file_size (int): maximum file size allowed.
        site_url (str): endpoint url.

    Returns:
        bool: True if valid, false otherwise.
    """
    if not site_url:
        return True

    parsed = urlparse(site_url)

    if not parsed.scheme.startswith("http"):
        return True

    if max_file_size is None:
        return False

    return max_file_size >= 0


def _validate_ip_network(network: str) -> bool:
    """Validate IP network.

    Args:
        network (str): IP network range.

    Returns:
        bool: True if valid, false otherwise.
    """
    if not network:
        return True

    try:
        ip_network(network)
    except ValueError:
        return False

    return True


def _validate_data(config_data: Dict[str, Any], relation_data: Dict[str, Any]) -> bool:
    """Validates passed information.

    Args:
        config_data (Dict[str, Any]): configuration information.
        relation_data (Dict[str, Any]): relation information

    Raises:
        ValueError: when config and/or relation data is not valid.
    """
    config_validators = {
        "site_url": lambda value, _: isinstance(value, str)
        if value is not None
        else True,
        "max_file_size": lambda value, values: _validate_max_file_size(
            value, values.get("site_url")
        ),
        "ingress_whitelist_source_range": lambda value, _: _validate_ip_network(value),
        "tls_secret_name": lambda value, _: isinstance(value, str)
        if value is not None
        else True,
    }
    relation_validators = {
        "prometheus_hostname": lambda value, _: (
            isinstance(value, str) and len(value) > 0
        ),
        "prometheus_port": lambda value, _: (
            isinstance(value, str) and len(value) > 0 and int(value) > 0
        ),
    }
    problems = []

    for key, validator in config_validators.items():
        valid = validator(config_data.get(key), config_data)

        if not valid:
            problems.append(key)

    for key, validator in relation_validators.items():
        valid = validator(relation_data.get(key), relation_data)

        if not valid:
            problems.append(key)

    if len(problems) > 0:
        logger.debug(relation_data)
        raise ValueError("Errors found in: {}".format(", ".join(problems)))

    return True


def _make_pod_ports(port: int) -> List[Dict[str, Any]]:
    """Generate pod ports details.

    Args:
        port (int): port to expose.

    Returns:
        List[Dict[str, Any]]: pod port details.
    """
    return [{"name": "grafana", "containerPort": port, "protocol": "TCP"}]


def _make_pod_envconfig(
    config: Dict[str, Any], relation_state: Dict[str, Any]
) -> Dict[str, Any]:
    """Generate pod environment configuration.

    Args:
        config (Dict[str, Any]): configuration information.
        relation_state (Dict[str, Any]): relation state information.

    Returns:
        Dict[str, Any]: pod environment configuration.
    """
    envconfig = {}

    return envconfig


def _make_pod_ingress_resources(
    config: Dict[str, Any], app_name: str, port: int
) -> List[Dict[str, Any]]:
    """Generate pod ingress resources.

    Args:
        config (Dict[str, Any]): configuration information.
        app_name (str): application name.
        port (int): port to expose.

    Returns:
        List[Dict[str, Any]]: pod ingress resources.
    """
    site_url = config.get("site_url")

    if not site_url:
        return

    parsed = urlparse(site_url)

    if not parsed.scheme.startswith("http"):
        return

    max_file_size = config["max_file_size"]
    ingress_whitelist_source_range = config["ingress_whitelist_source_range"]

    annotations = {
        "nginx.ingress.kubernetes.io/proxy-body-size": "{}".format(
            str(max_file_size) + "m" if max_file_size > 0 else max_file_size
        ),
    }

    if ingress_whitelist_source_range:
        annotations[
            "nginx.ingress.kubernetes.io/whitelist-source-range"
        ] = ingress_whitelist_source_range

    ingress_spec_tls = None

    if parsed.scheme == "https":
        ingress_spec_tls = [{"hosts": [parsed.hostname]}]
        tls_secret_name = config["tls_secret_name"]
        if tls_secret_name:
            ingress_spec_tls[0]["secretName"] = tls_secret_name
    else:
        annotations["nginx.ingress.kubernetes.io/ssl-redirect"] = "false"

    ingress = {
        "name": "{}-ingress".format(app_name),
        "annotations": annotations,
        "spec": {
            "rules": [
                {
                    "host": parsed.hostname,
                    "http": {
                        "paths": [
                            {
                                "path": "/",
                                "backend": {
                                    "serviceName": app_name,
                                    "servicePort": port,
                                },
                            }
                        ]
                    },
                }
            ]
        },
    }
    if ingress_spec_tls:
        ingress["spec"]["tls"] = ingress_spec_tls

    return [ingress]


def _make_pod_files(
    config: Dict[str, Any], relation: Dict[str, Any]
) -> List[Dict[str, Any]]:
    """Generating ConfigMap information

    Args:
        config (Dict[str, Any]): configuration information.
        relation (Dict[str, Any]): relation information.

    Returns:
        List[Dict[str, Any]]: ConfigMap information.
    """
    template_data = {**config, **relation}
    dashboards = []

    if config.get("osm_dashboards", False):
        dashboards.extend(
            [
                {
                    "path": "kafka_exporter_dashboard.json",
                    "content": Path("files/kafka_exporter_dashboard.json").read_text(),
                },
                {
                    "path": "mongodb_exporter_dashboard.json",
                    "content": Path(
                        "files/mongodb_exporter_dashboard.json"
                    ).read_text(),
                },
                {
                    "path": "mysql_exporter_dashboard.json",
                    "content": Path("files/mysql_exporter_dashboard.json").read_text(),
                },
                {
                    "path": "nodes_exporter_dashboard.json",
                    "content": Path("files/nodes_exporter_dashboard.json").read_text(),
                },
                {
                    "path": "summary_dashboard.json",
                    "content": Path("files/summary_dashboard.json").read_text(),
                },
            ]
        )

    dashboards.append(
        {
            "path": "dashboard_osm.yaml",
            "content": Path("files/default_dashboards.yaml").read_text(),
        }
    )

    files = [
        {
            "name": "dashboards",
            "mountPath": "/etc/grafana/provisioning/dashboards/",
            "files": dashboards,
        },
        {
            "name": "datasources",
            "mountPath": "/etc/grafana/provisioning/datasources/",
            "files": [
                {
                    "path": "datasource_prometheus.yaml",
                    "content": Template(
                        Path("files/default_dashboards.yaml").read_text()
                    ).substitute(template_data),
                }
            ],
        },
    ]

    return files


def _make_readiness_probe(port: int) -> Dict[str, Any]:
    """Generate readiness probe.

    Args:
        port (int): service port.

    Returns:
        Dict[str, Any]: readiness probe.
    """
    return {
        "httpGet": {
            "path": "/api/health",
            "port": port,
        },
        "initialDelaySeconds": 10,
        "periodSeconds": 10,
        "timeoutSeconds": 5,
        "successThreshold": 1,
        "failureThreshold": 3,
    }


def _make_liveness_probe(port: int) -> Dict[str, Any]:
    """Generate liveness probe.

    Args:
        port (int): service port.

    Returns:
        Dict[str, Any]: liveness probe.
    """
    return {
        "httpGet": {
            "path": "/api/health",
            "port": port,
        },
        "initialDelaySeconds": 60,
        "timeoutSeconds": 30,
        "failureThreshold": 10,
    }


def make_pod_spec(
    image_info: Dict[str, str],
    config: Dict[str, Any],
    relation_state: Dict[str, Any],
    app_name: str = "grafana",
    port: int = 3000,
) -> Dict[str, Any]:
    """Generate the pod spec information.

    Args:
        image_info (Dict[str, str]): Object provided by
                                     OCIImageResource("image").fetch().
        config (Dict[str, Any]): Configuration information.
        relation_state (Dict[str, Any]): Relation state information.
        app_name (str, optional): Application name. Defaults to "ro".
        port (int, optional): Port for the container. Defaults to 9090.

    Returns:
        Dict[str, Any]: Pod spec dictionary for the charm.
    """
    if not image_info:
        return None

    _validate_data(config, relation_state)

    ports = _make_pod_ports(port)
    env_config = _make_pod_envconfig(config, relation_state)
    files = _make_pod_files(config, relation_state)
    readiness_probe = _make_readiness_probe(port)
    liveness_probe = _make_liveness_probe(port)
    ingress_resources = _make_pod_ingress_resources(config, app_name, port)

    return {
        "version": 3,
        "containers": [
            {
                "name": app_name,
                "imageDetails": image_info,
                "imagePullPolicy": "Always",
                "ports": ports,
                "envConfig": env_config,
                "volumeConfig": files,
                "kubernetes": {
                    "readinessProbe": readiness_probe,
                    "livenessProbe": liveness_probe,
                },
            }
        ],
        "kubernetesResources": {
            "ingressResources": ingress_resources or [],
        },
    }
