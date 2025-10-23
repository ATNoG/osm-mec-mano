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

from charm import CharmError, OsmNgUiCharm, check_service_active

container_name = "ng-ui"
service_name = "ng-ui"

sites_default = """
server {
    listen       80;
    server_name  localhost;
    root   /usr/share/nginx/html;
    index  index.html index.htm;
    client_max_body_size 50M;

    location /osm {
        proxy_pass https://nbi:9999;
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_set_header Accept-Encoding "";
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
"""


@pytest.fixture
def harness(mocker: MockerFixture):
    mocker.patch("charm.KubernetesServicePatch", lambda x, y: None)
    harness = Harness(OsmNgUiCharm)
    harness.begin()
    container = harness.charm.unit.get_container("ng-ui")
    harness.set_can_connect(container, True)
    container.push("/etc/nginx/sites-available/default", sites_default, make_dirs=True)
    yield harness
    harness.cleanup()


def test_missing_relations(harness: Harness):
    harness.charm.on.config_changed.emit()
    assert type(harness.charm.unit.status) == BlockedStatus
    assert harness.charm.unit.status.message == "need nbi relation"


def test_ready(harness: Harness):
    _add_nbi_relation(harness)
    assert harness.charm.unit.status == ActiveStatus()


def test_container_stops_after_relation_broken(harness: Harness):
    harness.charm.on[container_name].pebble_ready.emit(container_name)
    container = harness.charm.unit.get_container(container_name)
    relation_id = _add_nbi_relation(harness)
    check_service_active(container, service_name)
    harness.remove_relation(relation_id)
    with pytest.raises(CharmError):
        check_service_active(container, service_name)
    assert type(harness.charm.unit.status) == BlockedStatus
    assert harness.charm.unit.status.message == "need nbi relation"


def _add_nbi_relation(harness: Harness):
    relation_id = harness.add_relation("nbi", "nbi")
    harness.add_relation_unit(relation_id, "nbi/0")
    harness.update_relation_data(relation_id, "nbi", {"host": "nbi", "port": "9999"})
    return relation_id
