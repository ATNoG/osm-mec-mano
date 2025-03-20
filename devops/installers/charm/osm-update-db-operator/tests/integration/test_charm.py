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

import base64
import logging
from pathlib import Path

import pytest
import yaml
from pytest_operator.plugin import OpsTest

logger = logging.getLogger(__name__)

METADATA = yaml.safe_load(Path("./metadata.yaml").read_text())


@pytest.mark.abort_on_fail
async def test_build_and_deploy(ops_test: OpsTest):
    """Build the charm-under-test and deploy it together with related charms.

    Assert on the unit status before any relations/configurations take place.
    """
    await ops_test.model.set_config({"update-status-hook-interval": "10s"})
    # build and deploy charm from local source folder
    charm = await ops_test.build_charm(".")
    resources = {
        "update-db-image": METADATA["resources"]["update-db-image"]["upstream-source"],
    }
    await ops_test.model.deploy(charm, resources=resources, application_name="update-db")
    await ops_test.model.wait_for_idle(apps=["update-db"], status="active", timeout=1000)
    assert ops_test.model.applications["update-db"].units[0].workload_status == "active"

    await ops_test.model.set_config({"update-status-hook-interval": "60m"})


def base64_encode(phrase: str) -> str:
    return base64.b64encode(phrase.encode("utf-8")).decode("utf-8")
