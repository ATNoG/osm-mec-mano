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

import asyncio
import logging
from pathlib import Path

import pytest
import yaml
from pytest_operator.plugin import OpsTest

logger = logging.getLogger(__name__)

METADATA = yaml.safe_load(Path("./metadata.yaml").read_text())
RO_APP = METADATA["name"]
KAFKA_CHARM = "kafka-k8s"
KAFKA_APP = "kafka"
MONGO_DB_CHARM = "mongodb-k8s"
MONGO_DB_APP = "mongodb"
ZOOKEEPER_CHARM = "zookeeper-k8s"
ZOOKEEPER_APP = "zookeeper"
APPS = [KAFKA_APP, MONGO_DB_APP, ZOOKEEPER_APP, RO_APP]


@pytest.mark.abort_on_fail
async def test_ro_is_deployed(ops_test: OpsTest):
    charm = await ops_test.build_charm(".")
    resources = {"ro-image": METADATA["resources"]["ro-image"]["upstream-source"]}

    await asyncio.gather(
        ops_test.model.deploy(charm, resources=resources, application_name=RO_APP, series="jammy"),
        ops_test.model.deploy(ZOOKEEPER_CHARM, application_name=ZOOKEEPER_APP, channel="stable"),
        ops_test.model.deploy(KAFKA_CHARM, application_name=KAFKA_APP, channel="stable"),
        ops_test.model.deploy(MONGO_DB_CHARM, application_name=MONGO_DB_APP, channel="5/edge"),
    )

    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=APPS,
            timeout=300,
        )
    assert ops_test.model.applications[RO_APP].status == "blocked"
    unit = ops_test.model.applications[RO_APP].units[0]
    assert unit.workload_status_message == "need kafka, mongodb relations"

    logger.info("Adding relations")
    await ops_test.model.add_relation(KAFKA_APP, ZOOKEEPER_APP)
    await ops_test.model.add_relation(
        "{}:mongodb".format(RO_APP), "{}:database".format(MONGO_DB_APP)
    )
    await ops_test.model.add_relation(RO_APP, KAFKA_APP)

    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=APPS,
            status="active",
            timeout=300,
        )


@pytest.mark.abort_on_fail
async def test_ro_scales(ops_test: OpsTest):
    logger.info("Scaling osm-ro")
    expected_units = 3
    assert len(ops_test.model.applications[RO_APP].units) == 1
    await ops_test.model.applications[RO_APP].scale(expected_units)
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=[RO_APP], status="active", timeout=1000, wait_for_exact_units=expected_units
        )


@pytest.mark.abort_on_fail
async def test_ro_blocks_without_kafka(ops_test: OpsTest):
    await asyncio.gather(ops_test.model.applications[KAFKA_APP].remove())
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(apps=[RO_APP])
    assert ops_test.model.applications[RO_APP].status == "blocked"
    for unit in ops_test.model.applications[RO_APP].units:
        assert unit.workload_status_message == "need kafka relation"
