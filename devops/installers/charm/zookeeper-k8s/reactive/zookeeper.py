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

from charms import layer
from charms.layer.caas_base import pod_spec_set
from charms.reactive import endpoint_from_flag
from charms.reactive import when, when_not, hook
from charms.reactive.flags import set_flag, clear_flag
from charmhelpers.core.hookenv import (
    log,
    metadata,
    config,
)

from charms.osm.k8s import is_pod_up, get_service_ip


@hook("upgrade-charm")
@when("leadership.is_leader")
def upgrade():
    clear_flag("zookeeper-k8s.configured")


@when("config.changed")
@when("leadership.is_leader")
def config_changed():
    clear_flag("zookeeper-k8s.configured")


@when_not("zookeeper-k8s.configured")
@when("leadership.is_leader")
def configure():
    layer.status.maintenance("Configuring zookeeper-k8s container")
    try:
        spec = make_pod_spec()
        log("set pod spec:\n{}".format(spec))
        pod_spec_set(spec)
        set_flag("zookeeper-k8s.configured")

    except Exception as e:
        layer.status.blocked("k8s spec failed to deploy: {}".format(e))


@when("zookeeper-k8s.configured")
def non_leader():
    layer.status.active("ready")


@when_not("leadership.is_leader")
def non_leaders_active():
    layer.status.active("ready")


@when("zookeeper.joined")
@when("zookeeper-k8s.configured")
def send_config():
    layer.status.maintenance("Sending Zookeeper configuration")
    if not is_pod_up("zookeeper"):
        log("The pod is not ready.")
        return

    zookeeper = endpoint_from_flag("zookeeper.joined")
    if zookeeper:
        service_ip = get_service_ip("zookeeper")
        if service_ip:
            zookeeper.send_connection(
                get_zookeeper_client_port(), get_zookeeper_client_port(), service_ip,
            )
            layer.status.active("ready")


def make_pod_spec():
    """Make pod specification for Kubernetes

    Returns:
        pod_spec: Pod specification for Kubernetes
    """
    with open("reactive/spec_template.yaml") as spec_file:
        pod_spec_template = spec_file.read()

    md = metadata()
    cfg = config()
    data = {"name": md.get("name"), "docker_image_path": cfg.get("image")}
    data.update(cfg)
    return pod_spec_template % data


def get_zookeeper_client_port():
    """Returns Zookeeper port"""
    cfg = config()
    return cfg.get("client-port")
