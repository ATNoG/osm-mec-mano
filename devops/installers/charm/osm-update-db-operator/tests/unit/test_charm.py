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

import unittest
from unittest.mock import Mock, patch

from ops.model import ActiveStatus, BlockedStatus, MaintenanceStatus
from ops.testing import Harness

from charm import UpgradeDBCharm


class TestCharm(unittest.TestCase):
    def setUp(self):
        self.harness = Harness(UpgradeDBCharm)
        self.addCleanup(self.harness.cleanup)
        self.harness.begin()

    def test_initial_config(self):
        self.assertEqual(self.harness.model.unit.status, MaintenanceStatus(""))

    def test_config_changed(self):
        self.harness.update_config({"mongodb-uri": "foo"})
        self.assertEqual(self.harness.model.unit.status, ActiveStatus())

    def test_config_changed_blocked(self):
        self.harness.update_config({"log-level": "DEBUG"})
        self.assertEqual(
            self.harness.model.unit.status,
            BlockedStatus("mongodb-uri and/or mysql-uri must be set"),
        )

    def test_update_db_fail_only_params(self):
        action_event = Mock(
            params={
                "current-version": 9,
                "target-version": 10,
                "mysql-only": True,
                "mongodb-only": True,
            }
        )
        self.harness.charm._on_update_db_action(action_event)
        self.assertEqual(
            action_event.fail.call_args,
            [("Failed DB Upgrade: cannot set both mysql-only and mongodb-only options to True",)],
        )

    @patch("charm.MongoUpgrade")
    @patch("charm.MysqlUpgrade")
    def test_update_db_mysql(self, mock_mysql_upgrade, mock_mongo_upgrade):
        self.harness.update_config({"mysql-uri": "foo"})
        action_event = Mock(
            params={
                "current-version": 9,
                "target-version": 10,
                "mysql-only": True,
                "mongodb-only": False,
            }
        )
        self.harness.charm._on_update_db_action(action_event)
        mock_mysql_upgrade().upgrade.assert_called_once()
        mock_mongo_upgrade.assert_not_called()

    @patch("charm.MongoUpgrade")
    @patch("charm.MysqlUpgrade")
    def test_update_db_mongo(self, mock_mysql_upgrade, mock_mongo_upgrade):
        self.harness.update_config({"mongodb-uri": "foo"})
        action_event = Mock(
            params={
                "current-version": 7,
                "target-version": 10,
                "mysql-only": False,
                "mongodb-only": True,
            }
        )
        self.harness.charm._on_update_db_action(action_event)
        mock_mongo_upgrade().upgrade.assert_called_once()
        mock_mysql_upgrade.assert_not_called()

    @patch("charm.MongoUpgrade")
    def test_update_db_not_configured_mongo_fail(self, mock_mongo_upgrade):
        action_event = Mock(
            params={
                "current-version": 7,
                "target-version": 10,
                "mysql-only": False,
                "mongodb-only": True,
            }
        )
        self.harness.charm._on_update_db_action(action_event)
        mock_mongo_upgrade.assert_not_called()
        self.assertEqual(
            action_event.fail.call_args,
            [("Failed DB Upgrade: mongo-uri not set",)],
        )

    @patch("charm.MysqlUpgrade")
    def test_update_db_not_configured_mysql_fail(self, mock_mysql_upgrade):
        action_event = Mock(
            params={
                "current-version": 7,
                "target-version": 10,
                "mysql-only": True,
                "mongodb-only": False,
            }
        )
        self.harness.charm._on_update_db_action(action_event)
        mock_mysql_upgrade.assert_not_called()
        self.assertEqual(
            action_event.fail.call_args,
            [("Failed DB Upgrade: mysql-uri not set",)],
        )

    @patch("charm.MongoUpgrade")
    @patch("charm.MysqlUpgrade")
    def test_update_db_mongodb_and_mysql(self, mock_mysql_upgrade, mock_mongo_upgrade):
        self.harness.update_config({"mongodb-uri": "foo"})
        self.harness.update_config({"mysql-uri": "foo"})
        action_event = Mock(
            params={
                "current-version": 7,
                "target-version": 10,
                "mysql-only": False,
                "mongodb-only": False,
            }
        )
        self.harness.charm._on_update_db_action(action_event)
        mock_mysql_upgrade().upgrade.assert_called_once()
        mock_mongo_upgrade().upgrade.assert_called_once()

    @patch("charm.MongoUpgrade")
    def test_apply_patch(self, mock_mongo_upgrade):
        self.harness.update_config({"mongodb-uri": "foo"})
        action_event = Mock(
            params={
                "bug-number": 57,
            }
        )
        self.harness.charm._on_apply_patch_action(action_event)
        mock_mongo_upgrade().apply_patch.assert_called_once()

    @patch("charm.MongoUpgrade")
    def test_apply_patch_fail(self, mock_mongo_upgrade):
        action_event = Mock(
            params={
                "bug-number": 57,
            }
        )
        self.harness.charm._on_apply_patch_action(action_event)
        mock_mongo_upgrade.assert_not_called()
        self.assertEqual(
            action_event.fail.call_args,
            [("Failed Patch Application: mongo-uri not set",)],
        )
