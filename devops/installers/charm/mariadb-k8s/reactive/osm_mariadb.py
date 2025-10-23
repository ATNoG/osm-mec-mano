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

from charms.layer.caas_base import pod_spec_set
from charms.reactive import when, when_not, hook
from charms.reactive import endpoint_from_flag
from charms.reactive.flags import set_flag, get_state, clear_flag

from charmhelpers.core.hookenv import (
    log,
    metadata,
    config,
    application_name,
)
from charms import layer
from charms.osm.k8s import is_pod_up, get_service_ip


@hook("upgrade-charm")
@when("leadership.is_leader")
def upgrade():
    clear_flag("mariadb-k8s.configured")


@when("config.changed")
@when("leadership.is_leader")
def restart():
    clear_flag("mariadb-k8s.configured")


@when_not("mariadb-k8s.configured")
@when("leadership.is_leader")
def configure():
    layer.status.maintenance("Configuring mariadb-k8s container")

    spec = make_pod_spec()
    log("set pod spec:\n{}".format(spec))
    pod_spec_set(spec)

    set_flag("mariadb-k8s.configured")


@when("mariadb-k8s.configured")
def set_mariadb_active():
    layer.status.active("ready")


@when_not("leadership.is_leader")
def non_leaders_active():
    layer.status.active("ready")


@when("mariadb-k8s.configured", "mysql.database.requested")
def provide_database():
    mysql = endpoint_from_flag("mysql.database.requested")

    if not is_pod_up("mysql"):
        log("The pod is not ready.")
        return

    for request, application in mysql.database_requests().items():
        try:

            log("request -> {0} for app -> {1}".format(request, application))
            user = get_state("user")
            password = get_state("password")
            database_name = get_state("database")
            root_password = get_state("root_password")

            log("db params: {0}:{1}@{2}".format(user, password, database_name))

            service_ip = get_service_ip("mysql")
            if service_ip:
                mysql.provide_database(
                    request_id=request,
                    host=service_ip,
                    port=3306,
                    database_name=database_name,
                    user=user,
                    password=password,
                    root_password=root_password,
                )
                mysql.mark_complete()
        except Exception as e:
            log("Exception while providing database: {}".format(e))


def make_pod_spec():
    """Make pod specification for Kubernetes

    Returns:
        pod_spec: Pod specification for Kubernetes
    """
    if config().get("ha-mode"):
        with open("reactive/spec_template_ha.yaml") as spec_file:
            pod_spec_template = spec_file.read()
        image = config().get("ha-image")
    else:
        with open("reactive/spec_template.yaml") as spec_file:
            pod_spec_template = spec_file.read()
        image = config().get("image")

    md = metadata()
    cfg = config()

    user = cfg.get("user")
    password = cfg.get("password")
    database = cfg.get("database")
    root_password = cfg.get("root_password")
    app_name = application_name()

    set_flag("user", user)
    set_flag("password", password)
    set_flag("database", database)
    set_flag("root_password", root_password)

    data = {
        "name": md.get("name"),
        "docker_image": image,
        "application_name": app_name,
    }
    data.update(cfg)
    return pod_spec_template % data
