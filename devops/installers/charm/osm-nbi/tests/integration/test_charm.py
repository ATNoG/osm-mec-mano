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
import shlex
from pathlib import Path

import pytest
import yaml
from pytest_operator.plugin import OpsTest

logger = logging.getLogger(__name__)

METADATA = yaml.safe_load(Path("./metadata.yaml").read_text())
NBI_APP = METADATA["name"]
KAFKA_CHARM = "kafka-k8s"
KAFKA_APP = "kafka"
MARIADB_CHARM = "charmed-osm-mariadb-k8s"
MARIADB_APP = "mariadb"
MONGO_DB_CHARM = "mongodb-k8s"
MONGO_DB_APP = "mongodb"
KEYSTONE_CHARM = "osm-keystone"
KEYSTONE_APP = "keystone"
PROMETHEUS_CHARM = "osm-prometheus"
PROMETHEUS_APP = "prometheus"
ZOOKEEPER_CHARM = "zookeeper-k8s"
ZOOKEEPER_APP = "zookeeper"
INGRESS_CHARM = "nginx-ingress-integrator"
INGRESS_APP = "ingress"
APPS = [KAFKA_APP, MONGO_DB_APP, MARIADB_APP, ZOOKEEPER_APP, KEYSTONE_APP, PROMETHEUS_APP, NBI_APP]


@pytest.mark.abort_on_fail
async def test_nbi_is_deployed(ops_test: OpsTest):
    charm = await ops_test.build_charm(".")
    resources = {"nbi-image": METADATA["resources"]["nbi-image"]["upstream-source"]}

    await asyncio.gather(
        ops_test.model.deploy(
            charm, resources=resources, application_name=NBI_APP, series="jammy"
        ),
        ops_test.model.deploy(KAFKA_CHARM, application_name=KAFKA_APP, channel="stable"),
        ops_test.model.deploy(MONGO_DB_CHARM, application_name=MONGO_DB_APP, channel="5/edge"),
        ops_test.model.deploy(MARIADB_CHARM, application_name=MARIADB_APP, channel="stable"),
        ops_test.model.deploy(ZOOKEEPER_CHARM, application_name=ZOOKEEPER_APP, channel="stable"),
        ops_test.model.deploy(PROMETHEUS_CHARM, application_name=PROMETHEUS_APP, channel="stable"),
    )
    # Keystone charm has to be deployed differently since
    # bug https://github.com/juju/python-libjuju/issues/766
    # prevents setting correctly the resources
    keystone_image = "opensourcemano/keystone:testing-daily"
    cmd = f"juju deploy {KEYSTONE_CHARM} {KEYSTONE_APP} --resource keystone-image={keystone_image} --channel=latest/beta --series jammy"
    await ops_test.run(*shlex.split(cmd), check=True)

    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=APPS,
        )
    assert ops_test.model.applications[NBI_APP].status == "blocked"
    unit = ops_test.model.applications[NBI_APP].units[0]
    assert unit.workload_status_message == "need kafka, mongodb, prometheus, keystone relations"

    logger.info("Adding relations for other components")
    await ops_test.model.add_relation(KAFKA_APP, ZOOKEEPER_APP)
    await ops_test.model.add_relation(MARIADB_APP, KEYSTONE_APP)

    logger.info("Adding relations for NBI")
    await ops_test.model.add_relation(
        "{}:mongodb".format(NBI_APP), "{}:database".format(MONGO_DB_APP)
    )
    await ops_test.model.add_relation(NBI_APP, KAFKA_APP)
    await ops_test.model.add_relation(NBI_APP, PROMETHEUS_APP)
    await ops_test.model.add_relation(NBI_APP, KEYSTONE_APP)

    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=APPS,
            status="active",
        )


@pytest.mark.abort_on_fail
async def test_nbi_scales_up(ops_test: OpsTest):
    logger.info("Scaling up osm-nbi")
    expected_units = 3
    assert len(ops_test.model.applications[NBI_APP].units) == 1
    await ops_test.model.applications[NBI_APP].scale(expected_units)
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=[NBI_APP], status="active", wait_for_exact_units=expected_units
        )


@pytest.mark.abort_on_fail
@pytest.mark.parametrize(
    "relation_to_remove", [KAFKA_APP, MONGO_DB_APP, PROMETHEUS_APP, KEYSTONE_APP]
)
async def test_nbi_blocks_without_relation(ops_test: OpsTest, relation_to_remove):
    logger.info("Removing relation: %s", relation_to_remove)
    # mongoDB relation is named "database"
    local_relation = relation_to_remove
    if local_relation == MONGO_DB_APP:
        local_relation = "database"
    await asyncio.gather(
        ops_test.model.applications[relation_to_remove].remove_relation(local_relation, NBI_APP)
    )
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(apps=[NBI_APP])
    assert ops_test.model.applications[NBI_APP].status == "blocked"
    for unit in ops_test.model.applications[NBI_APP].units:
        assert unit.workload_status_message == f"need {relation_to_remove} relation"
    await ops_test.model.add_relation(NBI_APP, relation_to_remove)
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=APPS,
            status="active",
        )


@pytest.mark.abort_on_fail
async def test_nbi_action_debug_mode_disabled(ops_test: OpsTest):
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=APPS,
            status="active",
        )
    logger.info("Running action 'get-debug-mode-information'")
    action = (
        await ops_test.model.applications[NBI_APP]
        .units[0]
        .run_action("get-debug-mode-information")
    )
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(apps=[NBI_APP])
    status = await ops_test.model.get_action_status(uuid_or_prefix=action.entity_id)
    assert status[action.entity_id] == "failed"


@pytest.mark.abort_on_fail
async def test_nbi_action_debug_mode_enabled(ops_test: OpsTest):
    await ops_test.model.applications[NBI_APP].set_config({"debug-mode": "true"})
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=APPS,
            status="active",
        )
    logger.info("Running action 'get-debug-mode-information'")
    # list of units is not ordered
    unit_id = list(
        filter(
            lambda x: (x.entity_id == f"{NBI_APP}/0"), ops_test.model.applications[NBI_APP].units
        )
    )[0]
    action = await unit_id.run_action("get-debug-mode-information")
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(apps=[NBI_APP])
    status = await ops_test.model.get_action_status(uuid_or_prefix=action.entity_id)
    message = await ops_test.model.get_action_output(action_uuid=action.entity_id)
    assert status[action.entity_id] == "completed"
    assert "command" in message
    assert "password" in message


@pytest.mark.abort_on_fail
async def test_nbi_integration_ingress(ops_test: OpsTest):
    # Temporal workaround due to python-libjuju 2.9.42.2 bug fixed in
    # https://github.com/juju/python-libjuju/pull/854
    # To be replaced when juju version 2.9.43 is used.
    cmd = f"juju deploy {INGRESS_CHARM} {INGRESS_APP} --channel stable"
    await ops_test.run(*shlex.split(cmd), check=True)

    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=APPS + [INGRESS_APP],
        )

    await ops_test.model.add_relation(NBI_APP, INGRESS_APP)
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=APPS + [INGRESS_APP],
            status="active",
        )
