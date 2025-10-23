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
# Learn more about testing at: https://juju.is/docs/sdk/testing

import pytest
from ops.model import ActiveStatus, BlockedStatus
from ops.testing import Harness
from pytest_mock import MockerFixture

from charm import CharmError, OsmMonCharm, check_service_active

container_name = "mon"
service_name = "mon"


@pytest.fixture
def harness(mocker: MockerFixture):
    mocker.patch("charm.KubernetesServicePatch", lambda x, y: None)
    harness = Harness(OsmMonCharm)
    harness.begin()
    harness.container_pebble_ready(container_name)
    yield harness
    harness.cleanup()


def test_missing_relations(harness: Harness):
    harness.charm.on.config_changed.emit()
    assert type(harness.charm.unit.status) == BlockedStatus
    assert all(
        relation in harness.charm.unit.status.message
        for relation in ["mongodb", "kafka", "prometheus", "keystone"]
    )


def test_ready(harness: Harness):
    _add_relations(harness)
    assert harness.charm.unit.status == ActiveStatus()


def test_container_stops_after_relation_broken(harness: Harness):
    harness.charm.on[container_name].pebble_ready.emit(container_name)
    container = harness.charm.unit.get_container(container_name)
    relation_ids = _add_relations(harness)
    check_service_active(container, service_name)
    harness.remove_relation(relation_ids[0])
    with pytest.raises(CharmError):
        check_service_active(container, service_name)


def _add_relations(harness: Harness):
    relation_ids = []
    # Add mongo relation
    relation_id = harness.add_relation("mongodb", "mongodb")
    harness.add_relation_unit(relation_id, "mongodb/0")
    harness.update_relation_data(
        relation_id,
        "mongodb",
        {"uris": "mongodb://:1234", "username": "user", "password": "password"},
    )
    relation_ids.append(relation_id)
    # Add kafka relation
    relation_id = harness.add_relation("kafka", "kafka")
    harness.add_relation_unit(relation_id, "kafka/0")
    harness.update_relation_data(relation_id, "kafka", {"host": "kafka", "port": "9092"})
    relation_ids.append(relation_id)
    # Add prometheus relation
    relation_id = harness.add_relation("prometheus", "prometheus")
    harness.add_relation_unit(relation_id, "prometheus/0")
    harness.update_relation_data(
        relation_id, "prometheus", {"hostname": "prometheus", "port": "9090"}
    )
    relation_ids.append(relation_id)
    # Add keystone relation
    relation_id = harness.add_relation("keystone", "keystone")
    harness.add_relation_unit(relation_id, "keystone/0")
    harness.update_relation_data(
        relation_id,
        "keystone",
        {
            "host": "host",
            "port": "port",
            "user_domain_name": "user_domain_name",
            "project_domain_name": "project_domain_name",
            "username": "username",
            "password": "password",
            "service": "service",
            "keystone_db_password": "keystone_db_password",
            "region_id": "region_id",
            "admin_username": "admin_username",
            "admin_password": "admin_password",
            "admin_project_name": "admin_project_name",
        },
    )
    relation_ids.append(relation_id)
    return relation_ids
