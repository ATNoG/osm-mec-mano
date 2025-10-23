#!/usr/bin/env python3
#######################################################################################
# Copyright ETSI Contributors and Others.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#######################################################################################

import asyncio
import logging
import shlex
from pathlib import Path

import pytest
import yaml
from pytest_operator.plugin import OpsTest

logger = logging.getLogger(__name__)

METADATA = yaml.safe_load(Path("./metadata.yaml").read_text())
VCA_APP = "osm-vca"

LCM_CHARM = "osm-lcm"
LCM_APP = "lcm"
KAFKA_CHARM = "kafka-k8s"
KAFKA_APP = "kafka"
MONGO_DB_CHARM = "mongodb-k8s"
MONGO_DB_APP = "mongodb"
RO_CHARM = "osm-ro"
RO_APP = "ro"
ZOOKEEPER_CHARM = "zookeeper-k8s"
ZOOKEEPER_APP = "zookeeper"
LCM_APPS = [KAFKA_APP, MONGO_DB_APP, ZOOKEEPER_APP, RO_APP, LCM_APP]
MON_CHARM = "osm-mon"
MON_APP = "mon"
KEYSTONE_CHARM = "osm-keystone"
KEYSTONE_APP = "keystone"
MARIADB_CHARM = "charmed-osm-mariadb-k8s"
MARIADB_APP = "mariadb"
PROMETHEUS_CHARM = "osm-prometheus"
PROMETHEUS_APP = "prometheus"
MON_APPS = [
    KAFKA_APP,
    ZOOKEEPER_APP,
    KEYSTONE_APP,
    MONGO_DB_APP,
    MARIADB_APP,
    PROMETHEUS_APP,
    MON_APP,
]


@pytest.mark.abort_on_fail
async def test_build_and_deploy(ops_test: OpsTest):
    """Build the charm osm-vca-integrator-k8s and deploy it together with related charms.

    Assert on the unit status before any relations/configurations take place.
    """
    charm = await ops_test.build_charm(".")
    await ops_test.model.deploy(charm, application_name=VCA_APP, series="jammy")
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=[VCA_APP],
            status="blocked",
        )
    assert ops_test.model.applications[VCA_APP].units[0].workload_status == "blocked"


@pytest.mark.abort_on_fail
async def test_vca_configuration(ops_test: OpsTest):
    controllers = (Path.home() / ".local/share/juju/controllers.yaml").read_text()
    accounts = (Path.home() / ".local/share/juju/accounts.yaml").read_text()
    public_key = (Path.home() / ".local/share/juju/ssh/juju_id_rsa.pub").read_text()
    await ops_test.model.applications[VCA_APP].set_config(
        {
            "controllers": controllers,
            "accounts": accounts,
            "public-key": public_key,
            "k8s-cloud": "microk8s",
        }
    )
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=[VCA_APP],
            status="active",
        )


@pytest.mark.abort_on_fail
async def test_vca_integration_lcm(ops_test: OpsTest):
    lcm_deploy_cmd = f"juju deploy {LCM_CHARM} {LCM_APP} --resource lcm-image=opensourcemano/lcm:testing-daily --channel=latest/beta --series=jammy"
    ro_deploy_cmd = f"juju deploy {RO_CHARM} {RO_APP} --resource ro-image=opensourcemano/ro:testing-daily --channel=latest/beta --series=jammy"

    await asyncio.gather(
        # LCM and RO charms have to be deployed differently since
        # bug https://github.com/juju/python-libjuju/pull/820
        # fails to parse assumes
        ops_test.run(*shlex.split(lcm_deploy_cmd), check=True),
        ops_test.run(*shlex.split(ro_deploy_cmd), check=True),
        ops_test.model.deploy(KAFKA_CHARM, application_name=KAFKA_APP, channel="stable"),
        ops_test.model.deploy(MONGO_DB_CHARM, application_name=MONGO_DB_APP, channel="5/edge"),
        ops_test.model.deploy(ZOOKEEPER_CHARM, application_name=ZOOKEEPER_APP, channel="stable"),
    )
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=LCM_APPS,
        )
    # wait for MongoDB to be active before relating RO to it
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(apps=[MONGO_DB_APP], status="active")
    logger.info("Adding relations")
    await ops_test.model.add_relation(KAFKA_APP, ZOOKEEPER_APP)
    await ops_test.model.add_relation(
        "{}:mongodb".format(RO_APP), "{}:database".format(MONGO_DB_APP)
    )
    await ops_test.model.add_relation(RO_APP, KAFKA_APP)
    # LCM specific
    await ops_test.model.add_relation(
        "{}:mongodb".format(LCM_APP), "{}:database".format(MONGO_DB_APP)
    )
    await ops_test.model.add_relation(LCM_APP, KAFKA_APP)
    await ops_test.model.add_relation(LCM_APP, RO_APP)

    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=LCM_APPS,
            status="active",
        )

    logger.info("Adding relation VCA LCM")
    await ops_test.model.add_relation(VCA_APP, LCM_APP)
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=[VCA_APP, LCM_APP],
            status="active",
        )


@pytest.mark.abort_on_fail
async def test_vca_integration_mon(ops_test: OpsTest):
    keystone_image = "opensourcemano/keystone:testing-daily"
    keystone_deploy_cmd = f"juju deploy {KEYSTONE_CHARM} {KEYSTONE_APP} --resource keystone-image={keystone_image} --channel=latest/beta --series jammy"
    mon_deploy_cmd = f"juju deploy {MON_CHARM} {MON_APP} --resource mon-image=opensourcemano/mon:testing-daily --channel=latest/beta --series=jammy"
    await asyncio.gather(
        # MON charm has to be deployed differently since
        # bug https://github.com/juju/python-libjuju/issues/820
        # fails to parse assumes
        ops_test.run(*shlex.split(mon_deploy_cmd), check=True),
        ops_test.model.deploy(MARIADB_CHARM, application_name=MARIADB_APP, channel="stable"),
        ops_test.model.deploy(PROMETHEUS_CHARM, application_name=PROMETHEUS_APP, channel="stable"),
        # Keystone charm has to be deployed differently since
        # bug https://github.com/juju/python-libjuju/issues/766
        # prevents setting correctly the resources
        ops_test.run(*shlex.split(keystone_deploy_cmd), check=True),
    )
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=MON_APPS,
        )

    logger.info("Adding relations")
    await ops_test.model.add_relation(MARIADB_APP, KEYSTONE_APP)
    # MON specific
    await ops_test.model.add_relation(
        "{}:mongodb".format(MON_APP), "{}:database".format(MONGO_DB_APP)
    )
    await ops_test.model.add_relation(MON_APP, KAFKA_APP)
    await ops_test.model.add_relation(MON_APP, KEYSTONE_APP)
    await ops_test.model.add_relation(MON_APP, PROMETHEUS_APP)

    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=MON_APPS,
            status="active",
        )

    logger.info("Adding relation VCA MON")
    await ops_test.model.add_relation(VCA_APP, MON_APP)
    async with ops_test.fast_forward():
        await ops_test.model.wait_for_idle(
            apps=[VCA_APP, MON_APP],
            status="active",
        )
