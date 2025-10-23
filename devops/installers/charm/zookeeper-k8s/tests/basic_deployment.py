#!/usr/bin/python3
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

import unittest
import zaza.model as model
from kazoo.client import KazooClient


def get_zookeeper_uri():
    zookeeper_uri = ""
    zookeeper_units = model.get_status().applications["zookeeper-k8s"]["units"]
    for i, unit_name in enumerate(zookeeper_units.keys()):
        if i:
            zookeeper_uri += ","
        unit_ip = zookeeper_units[unit_name]["address"]
        unit_port = 2181
        zookeeper_uri += "{}:{}".format(unit_ip, unit_port)

    return zookeeper_uri


class BasicDeployment(unittest.TestCase):
    def test_get_zookeeper_uri(self):
        get_zookeeper_uri()

    def test_zookeeper_connection(self):
        zookeeper_uri = get_zookeeper_uri()
        zk = KazooClient(zookeeper_uri)
        self.assertEqual(zk.state, "LOST")
        zk.start()
        self.assertEqual(zk.state, "CONNECTED")
        zk.stop()
        self.assertEqual(zk.state, "LOST")

    def test_zookeeper_create_node(self):
        zookeeper_uri = get_zookeeper_uri()
        zk = KazooClient(hosts=zookeeper_uri, read_only=True)
        zk.start()

        zk.ensure_path("/create/new")
        self.assertTrue(zk.exists("/create/new"))

        zk.create("/create/new/node", b"a value")
        self.assertTrue(zk.exists("/create/new/node"))

        zk.stop()

    def test_zookeeper_reading_data(self):
        zookeeper_uri = get_zookeeper_uri()
        zk = KazooClient(hosts=zookeeper_uri, read_only=True)
        zk.start()

        zk.ensure_path("/reading/data")
        zk.create("/reading/data/node", b"a value")

        data, stat = zk.get("/reading/data")
        self.assertEqual(data.decode("utf-8"), "")

        children = zk.get_children("/reading/data")
        self.assertEqual(len(children), 1)
        self.assertEqual("node", children[0])

        data, stat = zk.get("/reading/data/node")
        self.assertEqual(data.decode("utf-8"), "a value")
        zk.stop()

    def test_zookeeper_updating_data(self):
        zookeeper_uri = get_zookeeper_uri()
        zk = KazooClient(hosts=zookeeper_uri, read_only=True)
        zk.start()

        zk.ensure_path("/updating/data")
        zk.create("/updating/data/node", b"a value")

        data, stat = zk.get("/updating/data/node")
        self.assertEqual(data.decode("utf-8"), "a value")

        zk.set("/updating/data/node", b"b value")
        data, stat = zk.get("/updating/data/node")
        self.assertEqual(data.decode("utf-8"), "b value")
        zk.stop()

    def test_zookeeper_deleting_data(self):
        zookeeper_uri = get_zookeeper_uri()
        zk = KazooClient(hosts=zookeeper_uri, read_only=True)
        zk.start()

        zk.ensure_path("/deleting/data")
        zk.create("/deleting/data/node", b"a value")

        zk.delete("/deleting/data/node", recursive=True)

        self.assertFalse(zk.exists("/deleting/data/node"))
        self.assertTrue(zk.exists("/deleting/data"))
        data, stat = zk.get("/deleting/data")
        self.assertEqual(stat.numChildren, 0)
        zk.delete("/deleting", recursive=True)
        self.assertFalse(zk.exists("/deleting"))
        zk.stop()
