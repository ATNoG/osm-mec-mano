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
from ops.model import ActiveStatus
from ops.testing import Harness
from pytest_mock import MockerFixture

from charm import JujuSimplestreamsCharm

container_name = "server"
service_name = "server"


@pytest.fixture
def harness(mocker: MockerFixture):
    mocker.patch("charm.KubernetesServicePatch", lambda x, y: None)
    harness = Harness(JujuSimplestreamsCharm)
    harness.begin()
    harness.charm.container.make_dir("/etc/nginx", make_parents=True)
    yield harness
    harness.cleanup()


def test_ready(harness: Harness):
    harness.charm.on.server_pebble_ready.emit(container_name)
    assert harness.charm.unit.status == ActiveStatus()


def test_add_metadata_action(harness: Harness, mocker: MockerFixture):
    harness.set_leader(True)
    remote_unit = f"{harness.charm.app.name}/1"
    relation_id = harness.add_relation("peer", harness.charm.app.name)
    harness.add_relation_unit(relation_id, remote_unit)
    event = mocker.Mock()
    event.params = {
        "region": "microstack",
        "auth-url": "localhost",
        "image-id": "id",
        "series": "focal",
    }
    harness.charm._on_add_image_metadata_action(event)
    # Harness not emitting relation changed event when in the action
    # I update application data in the peer relation.
    # Manually emitting it here:
    relation = harness.charm.model.get_relation("peer")
    harness.charm.on["peer"].relation_changed.emit(relation)
    assert harness.charm.container.exists("/app/static/simplestreams/images/streams/v1/index.json")
