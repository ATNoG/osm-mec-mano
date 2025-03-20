#!/usr/bin/env python3
# Copyright 2023 Canonical Ltd.
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
NG_UI_APP = METADATA["name"]

# Required charms (needed by NG UI)
NBI_CHARM = "osm-nbi"
NBI_APP = "nbi"
KAFKA_CHARM = "kafka-k8s"
KAFKA_APP = "kafka"
MONGO_DB_CHARM = "mongodb-k8s"
MONGO_DB_APP = "mongodb"
PROMETHEUS_CHARM = "osm-prometheus"
PROMETHEUS_APP = "prometheus"
KEYSTONE_CHARM = "osm-keystone"
KEYSTONE_APP = "keystone"
MYSQL_CHARM = "charmed-osm-mariadb-k8s"
MYSQL_APP = "mysql"
ZOOKEEPER_CHARM = "zookeeper-k8s"
ZOOKEEPER_APP = "zookeeper"

INGRESS_CHARM = "nginx-ingress-integrator"
INGRESS_APP = "ingress"

ALL_APPS = [
    NBI_APP,
    NG_UI_APP,
    KAFKA_APP,
    MONGO_DB_APP,
    PROMETHEUS_APP,
    KEYSTONE_APP,
    MYSQL_APP,
    ZOOKEEPER_APP,
]


@pytest.mark.abort_on_fail
async def test_ng_ui_is_deployed(ops_test: OpsTest):
    ng_ui_charm = await ops_test.build_charm(".")
    ng_ui_resources = {"ng-ui-image": METADATA["resources"]["ng-ui-image"]["upstream-source"]}
    keystone_image = "opensourcemano/keystone:testing-daily"
    keystone_deploy_cmd = f"juju deploy -m {ops_test.model_full_name} {KEYSTONE_CHARM} {KEYSTONE_APP} --resource keystone-image={keystone_image} --channel=latest/beta --series jammy"

    await asyncio.gather(
        ops_test.model.deploy(
            ng_ui_charm, resources=ng_ui_resources, application_name=NG_UI_APP, series="jammy"
        ),
        ops_test.model.deploy(
            NBI_CHARM, application_name=NBI_APP, channel="latest/beta", series="jammy"
        ),
        ops_test.model.deploy(KAFKA_CHARM, application_name=KAFKA_APP, channel="stable"),
        ops_test.model.deploy(MONGO_DB_CHARM, application_name=MONGO_DB_APP, channel="5/edge"),
        ops_test.model.deploy(PROMETHEUS_CHARM, application_name=PROMETHEUS_APP, channel="stable"),
        ops_test.model.deploy(ZOOKEEPER_CHARM, application_name=ZOOKEEPER_APP, channel="stable"),
        ops_test.model.deploy(MYSQL_CHARM, application_name=MYSQL_APP, channel="stable"),
        # Keystone is deployed separately because the juju python library has a bug where resources
        # are not properly deployed. See https://github.com/juju/python-libjuju/issues/766
        ops_test.run(*shlex.split(keystone_deploy_cmd), check=True),
    )

    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(apps=ALL_APPS, timeout=300)
    logger.info("Adding relations for other components")
    await asyncio.gather(
        ops_test.model.relate(MYSQL_APP, KEYSTONE_APP),
        ops_test.model.relate(KAFKA_APP, ZOOKEEPER_APP),
        ops_test.model.relate(KEYSTONE_APP, NBI_APP),
        ops_test.model.relate(KAFKA_APP, NBI_APP),
        ops_test.model.relate("{}:mongodb".format(NBI_APP), "{}:database".format(MONGO_DB_APP)),
        ops_test.model.relate(PROMETHEUS_APP, NBI_APP),
    )

    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(apps=ALL_APPS, timeout=300)

    assert ops_test.model.applications[NG_UI_APP].status == "blocked"
    unit = ops_test.model.applications[NG_UI_APP].units[0]
    assert unit.workload_status_message == "need nbi relation"

    logger.info("Adding relations for NG-UI")
    await ops_test.model.relate(NG_UI_APP, NBI_APP)

    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(apps=ALL_APPS, status="active", timeout=300)


@pytest.mark.abort_on_fail
async def test_ng_ui_scales_up(ops_test: OpsTest):
    logger.info("Scaling up osm-ng-ui")
    expected_units = 3
    assert len(ops_test.model.applications[NG_UI_APP].units) == 1
    await ops_test.model.applications[NG_UI_APP].scale(expected_units)
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=[NG_UI_APP], status="active", wait_for_exact_units=expected_units
        )


@pytest.mark.abort_on_fail
async def test_ng_ui_blocks_without_relation(ops_test: OpsTest):
    await asyncio.gather(ops_test.model.applications[NBI_APP].remove_relation(NBI_APP, NG_UI_APP))
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(apps=[NG_UI_APP])
    assert ops_test.model.applications[NG_UI_APP].status == "blocked"
    for unit in ops_test.model.applications[NG_UI_APP].units:
        assert unit.workload_status_message == "need nbi relation"
    await ops_test.model.relate(NG_UI_APP, NBI_APP)
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(apps=ALL_APPS, status="active")


@pytest.mark.abort_on_fail
async def test_ng_ui_integration_ingress(ops_test: OpsTest):
    # Temporal workaround due to python-libjuju 2.9.42.2 bug fixed in
    # https://github.com/juju/python-libjuju/pull/854
    # To be replaced when juju version 2.9.43 is used.
    cmd = f"juju deploy {INGRESS_CHARM} {INGRESS_APP} --channel stable"
    await ops_test.run(*shlex.split(cmd), check=True)

    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(apps=ALL_APPS + [INGRESS_APP])

    await ops_test.model.relate(NG_UI_APP, INGRESS_APP)
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(apps=ALL_APPS + [INGRESS_APP], status="active")
