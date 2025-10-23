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

import logging
import unittest
from unittest.mock import MagicMock, Mock, call, patch

import db_upgrade
from db_upgrade import (
    MongoPatch1837,
    MongoUpgrade,
    MongoUpgrade910,
    MongoUpgrade1012,
    MysqlUpgrade,
)

logger = logging.getLogger(__name__)


class TestUpgradeMongo910(unittest.TestCase):
    @patch("db_upgrade.MongoClient")
    def test_upgrade_mongo_9_10(self, mock_mongo_client):
        mock_db = MagicMock()
        alarms = Mock()
        alarms.find.return_value = [{"_id": "1", "alarm_status": "1"}]
        collection_dict = {"alarms": alarms, "other": {}}
        mock_db.list_collection_names.return_value = collection_dict
        mock_db.__getitem__.side_effect = collection_dict.__getitem__
        mock_mongo_client.return_value = {"osm": mock_db}
        MongoUpgrade910.upgrade("mongo_uri")
        alarms.update_one.assert_not_called()

    @patch("db_upgrade.MongoClient")
    def test_upgrade_mongo_9_10_no_alarms(self, mock_mongo_client):
        mock_db = Mock()
        mock_db.__getitem__ = Mock()

        mock_db.list_collection_names.return_value = {"other": {}}
        mock_db.alarms.return_value = None
        mock_mongo_client.return_value = {"osm": mock_db}
        self.assertIsNone(MongoUpgrade910.upgrade("mongo_uri"))

    @patch("db_upgrade.MongoClient")
    def test_upgrade_mongo_9_10_no_alarm_status(self, mock_mongo_client):
        mock_db = MagicMock()
        alarms = Mock()
        alarms.find.return_value = [{"_id": "1"}]
        collection_dict = {"alarms": alarms, "other": {}}
        mock_db.list_collection_names.return_value = collection_dict
        mock_db.__getitem__.side_effect = collection_dict.__getitem__
        mock_db.alarms.return_value = alarms
        mock_mongo_client.return_value = {"osm": mock_db}
        MongoUpgrade910.upgrade("mongo_uri")
        alarms.update_one.assert_called_once_with({"_id": "1"}, {"$set": {"alarm_status": "ok"}})


class TestUpgradeMongo1012(unittest.TestCase):
    def setUp(self):
        self.mock_db = MagicMock()
        self.nsrs = Mock()
        self.vnfrs = Mock()
        self.k8s_clusters = Mock()

    @patch("db_upgrade.MongoClient")
    def test_update_nsr_empty_nsrs(self, mock_mongo_client):
        self.nsrs.find.return_value = []
        collection_list = {"nsrs": self.nsrs}
        self.mock_db.__getitem__.side_effect = collection_list.__getitem__
        self.mock_db.list_collection_names.return_value = collection_list
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoUpgrade1012.upgrade("mongo_uri")

    @patch("db_upgrade.MongoClient")
    def test_update_nsr_empty_nsr(self, mock_mongo_client):
        nsr = MagicMock()
        nsr_values = {"_id": "2", "_admin": {}}
        nsr.__getitem__.side_effect = nsr_values.__getitem__
        nsr.items.return_value = []
        self.nsrs.find.return_value = [nsr]
        collection_list = {"nsrs": self.nsrs}
        self.mock_db.__getitem__.side_effect = collection_list.__getitem__
        self.mock_db.list_collection_names.return_value = collection_list
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoUpgrade1012.upgrade("mongo_uri")

    @patch("db_upgrade.MongoClient")
    def test_update_nsr_add_vim_message(self, mock_mongo_client):
        nsr = MagicMock()
        vim_info1 = {"vim_info_key1": {}}
        vim_info2 = {"vim_info_key2": {"vim_message": "Hello"}}
        nsr_items = {"nsr_item_key": [{"vim_info": vim_info1}, {"vim_info": vim_info2}]}
        nsr_values = {"_id": "2", "_admin": {}}
        nsr.__getitem__.side_effect = nsr_values.__getitem__
        nsr.items.return_value = nsr_items.items()
        self.nsrs.find.return_value = [nsr]
        collection_list = {"nsrs": self.nsrs}
        self.mock_db.__getitem__.side_effect = collection_list.__getitem__
        self.mock_db.list_collection_names.return_value = collection_list
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoUpgrade1012.upgrade("mongo_uri")
        expected_vim_info = {"vim_info_key1": {"vim_message": None}}
        expected_vim_info2 = {"vim_info_key2": {"vim_message": "Hello"}}
        self.assertEqual(vim_info1, expected_vim_info)
        self.assertEqual(vim_info2, expected_vim_info2)
        self.nsrs.update_one.assert_called_once_with({"_id": "2"}, {"$set": nsr_items})

    @patch("db_upgrade.MongoClient")
    def test_update_nsr_admin(self, mock_mongo_client):
        nsr = MagicMock()
        k8s = [{"k8scluster-uuid": "namespace"}, {"k8scluster-uuid": "kube-system:k8s"}]
        admin = {"deployed": {"K8s": k8s}}
        nsr_values = {"_id": "2", "_admin": admin}
        nsr.__getitem__.side_effect = nsr_values.__getitem__
        nsr_items = {}
        nsr.items.return_value = nsr_items.items()
        self.nsrs.find.return_value = [nsr]
        collection_list = {"nsrs": self.nsrs}
        self.mock_db.__getitem__.side_effect = collection_list.__getitem__
        self.mock_db.list_collection_names.return_value = collection_list
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoUpgrade1012.upgrade("mongo_uri")
        expected_k8s = [{"k8scluster-uuid": "namespace"}, {"k8scluster-uuid": "k8s"}]
        self.nsrs.update_one.assert_called_once_with(
            {"_id": "2"}, {"$set": {"_admin.deployed.K8s": expected_k8s}}
        )

    @patch("db_upgrade.MongoClient")
    def test_update_vnfr_empty_vnfrs(self, mock_mongo_client):
        self.vnfrs.find.return_value = [{"_id": "10", "vdur": []}]
        collection_list = {"vnfrs": self.vnfrs}
        self.mock_db.__getitem__.side_effect = collection_list.__getitem__
        self.mock_db.list_collection_names.return_value = collection_list
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoUpgrade1012.upgrade("mongo_uri")
        self.vnfrs.update_one.assert_called_once_with({"_id": "10"}, {"$set": {"vdur": []}})

    @patch("db_upgrade.MongoClient")
    def test_update_vnfr_no_vim_info(self, mock_mongo_client):
        vdur = {"other": {}}
        vnfr = {"_id": "10", "vdur": [vdur]}
        self.vnfrs.find.return_value = [vnfr]
        collection_list = {"vnfrs": self.vnfrs}
        self.mock_db.__getitem__.side_effect = collection_list.__getitem__
        self.mock_db.list_collection_names.return_value = collection_list
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoUpgrade1012.upgrade("mongo_uri")
        self.assertEqual(vdur, {"other": {}})
        self.vnfrs.update_one.assert_called_once_with({"_id": "10"}, {"$set": {"vdur": [vdur]}})

    @patch("db_upgrade.MongoClient")
    def test_update_vnfr_vim_message_not_conditions_matched(self, mock_mongo_client):
        vim_info = {"vim_message": "HelloWorld"}
        vim_infos = {"key1": vim_info, "key2": "value2"}
        vdur = {"vim_info": vim_infos, "other": {}}
        vnfr = {"_id": "10", "vdur": [vdur]}
        self.vnfrs.find.return_value = [vnfr]
        collection_list = {"vnfrs": self.vnfrs}
        self.mock_db.__getitem__.side_effect = collection_list.__getitem__
        self.mock_db.list_collection_names.return_value = collection_list
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoUpgrade1012.upgrade("mongo_uri")
        expected_vim_info = {"vim_message": "HelloWorld"}
        self.assertEqual(vim_info, expected_vim_info)
        self.vnfrs.update_one.assert_called_once_with({"_id": "10"}, {"$set": {"vdur": [vdur]}})

    @patch("db_upgrade.MongoClient")
    def test_update_vnfr_vim_message_is_missing(self, mock_mongo_client):
        vim_info = {"interfaces_backup": "HelloWorld"}
        vim_infos = {"key1": vim_info, "key2": "value2"}
        vdur = {"vim_info": vim_infos, "other": {}}
        vnfr = {"_id": "10", "vdur": [vdur]}
        self.vnfrs.find.return_value = [vnfr]
        collection_list = {"vnfrs": self.vnfrs}
        self.mock_db.__getitem__.side_effect = collection_list.__getitem__
        self.mock_db.list_collection_names.return_value = collection_list
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoUpgrade1012.upgrade("mongo_uri")
        expected_vim_info = {"vim_message": None, "interfaces_backup": "HelloWorld"}
        self.assertEqual(vim_info, expected_vim_info)
        self.vnfrs.update_one.assert_called_once_with({"_id": "10"}, {"$set": {"vdur": [vdur]}})

    @patch("db_upgrade.MongoClient")
    def test_update_vnfr_interfaces_backup_is_updated(self, mock_mongo_client):
        vim_info = {"interfaces": "HelloWorld", "vim_message": "ByeWorld"}
        vim_infos = {"key1": vim_info, "key2": "value2"}
        vdur = {"vim_info": vim_infos, "other": {}}
        vnfr = {"_id": "10", "vdur": [vdur]}
        self.vnfrs.find.return_value = [vnfr]
        collection_list = {"vnfrs": self.vnfrs}
        self.mock_db.__getitem__.side_effect = collection_list.__getitem__
        self.mock_db.list_collection_names.return_value = collection_list
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoUpgrade1012.upgrade("mongo_uri")
        expected_vim_info = {
            "interfaces": "HelloWorld",
            "vim_message": "ByeWorld",
            "interfaces_backup": "HelloWorld",
        }
        self.assertEqual(vim_info, expected_vim_info)
        self.vnfrs.update_one.assert_called_once_with({"_id": "10"}, {"$set": {"vdur": [vdur]}})

    @patch("db_upgrade.MongoClient")
    def test_update_k8scluster_empty_k8scluster(self, mock_mongo_client):
        self.k8s_clusters.find.return_value = []
        collection_list = {"k8sclusters": self.k8s_clusters}
        self.mock_db.__getitem__.side_effect = collection_list.__getitem__
        self.mock_db.list_collection_names.return_value = collection_list
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoUpgrade1012.upgrade("mongo_uri")

    @patch("db_upgrade.MongoClient")
    def test_update_k8scluster_replace_namespace_in_helm_chart(self, mock_mongo_client):
        helm_chart = {"id": "kube-system:Hello", "other": {}}
        k8s_cluster = {"_id": "8", "_admin": {"helm-chart": helm_chart}}
        self.k8s_clusters.find.return_value = [k8s_cluster]
        collection_list = {"k8sclusters": self.k8s_clusters}
        self.mock_db.__getitem__.side_effect = collection_list.__getitem__
        self.mock_db.list_collection_names.return_value = collection_list
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoUpgrade1012.upgrade("mongo_uri")
        expected_helm_chart = {"id": "Hello", "other": {}}
        expected_k8s_cluster = {"_id": "8", "_admin": {"helm-chart": expected_helm_chart}}
        self.k8s_clusters.update_one.assert_called_once_with(
            {"_id": "8"}, {"$set": expected_k8s_cluster}
        )

    @patch("db_upgrade.MongoClient")
    def test_update_k8scluster_replace_namespace_in_helm_chart_v3(self, mock_mongo_client):
        helm_chart_v3 = {"id": "kube-system:Hello", "other": {}}
        k8s_cluster = {"_id": "8", "_admin": {"helm-chart-v3": helm_chart_v3}}
        self.k8s_clusters.find.return_value = [k8s_cluster]
        collection_list = {"k8sclusters": self.k8s_clusters}
        self.mock_db.__getitem__.side_effect = collection_list.__getitem__
        self.mock_db.list_collection_names.return_value = collection_list
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoUpgrade1012.upgrade("mongo_uri")
        expected_helm_chart_v3 = {"id": "Hello", "other": {}}
        expected_k8s_cluster = {"_id": "8", "_admin": {"helm-chart-v3": expected_helm_chart_v3}}
        self.k8s_clusters.update_one.assert_called_once_with(
            {"_id": "8"}, {"$set": expected_k8s_cluster}
        )


class TestPatch1837(unittest.TestCase):
    def setUp(self):
        self.mock_db = MagicMock()
        self.vnfrs = Mock()
        self.nslcmops = Mock()

    @patch("db_upgrade.MongoClient")
    def test_update_vnfrs_params_no_vnfrs_or_nslcmops(self, mock_mongo_client):
        collection_dict = {"other": {}}
        self.mock_db.list_collection_names.return_value = collection_dict
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoPatch1837.patch("mongo_uri")

    @patch("db_upgrade.MongoClient")
    def test_update_vnfrs_params_no_kdur(self, mock_mongo_client):
        self.vnfrs.find.return_value = {"_id": "1"}
        collection_dict = {"vnfrs": self.vnfrs, "other": {}}
        self.mock_db.list_collection_names.return_value = collection_dict
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoPatch1837.patch("mongo_uri")

    @patch("db_upgrade.MongoClient")
    def test_update_vnfrs_params_kdur_without_additional_params(self, mock_mongo_client):
        kdur = [{"other": {}}]
        self.vnfrs.find.return_value = [{"_id": "1", "kdur": kdur}]
        collection_dict = {"vnfrs": self.vnfrs, "other": {}}
        self.mock_db.list_collection_names.return_value = collection_dict
        self.mock_db.__getitem__.side_effect = collection_dict.__getitem__
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoPatch1837.patch("mongo_uri")
        self.vnfrs.update_one.assert_called_once_with({"_id": "1"}, {"$set": {"kdur": kdur}})

    @patch("db_upgrade.MongoClient")
    def test_update_vnfrs_params_kdur_two_additional_params(self, mock_mongo_client):
        kdur1 = {"additionalParams": "additional_params", "other": {}}
        kdur2 = {"additionalParams": 4, "other": {}}
        kdur = [kdur1, kdur2]
        self.vnfrs.find.return_value = [{"_id": "1", "kdur": kdur}]
        collection_dict = {"vnfrs": self.vnfrs, "other": {}}
        self.mock_db.list_collection_names.return_value = collection_dict
        self.mock_db.__getitem__.side_effect = collection_dict.__getitem__
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoPatch1837.patch("mongo_uri")
        self.vnfrs.update_one.assert_called_once_with(
            {"_id": "1"}, {"$set": {"kdur": [kdur1, {"additionalParams": "4", "other": {}}]}}
        )

    @patch("db_upgrade.MongoClient")
    def test_update_nslcmops_params_no_nslcmops(self, mock_mongo_client):
        self.nslcmops.find.return_value = []
        collection_dict = {"nslcmops": self.nslcmops, "other": {}}
        self.mock_db.list_collection_names.return_value = collection_dict
        self.mock_db.__getitem__.side_effect = collection_dict.__getitem__
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoPatch1837.patch("mongo_uri")

    @patch("db_upgrade.MongoClient")
    def test_update_nslcmops_additional_params(self, mock_mongo_client):
        operation_params_list = {"additionalParamsForVnf": [1, 2, 3]}
        operation_params_dict = {"primitive_params": {"dict_key": 5}}
        nslcmops1 = {"_id": "1", "other": {}}
        nslcmops2 = {"_id": "2", "operationParams": operation_params_list, "other": {}}
        nslcmops3 = {"_id": "3", "operationParams": operation_params_dict, "other": {}}
        self.nslcmops.find.return_value = [nslcmops1, nslcmops2, nslcmops3]
        collection_dict = {"nslcmops": self.nslcmops, "other": {}}
        self.mock_db.list_collection_names.return_value = collection_dict
        self.mock_db.__getitem__.side_effect = collection_dict.__getitem__
        mock_mongo_client.return_value = {"osm": self.mock_db}
        MongoPatch1837.patch("mongo_uri")
        call1 = call(
            {"_id": "2"}, {"$set": {"operationParams": {"additionalParamsForVnf": "[1, 2, 3]"}}}
        )
        call2 = call(
            {"_id": "3"}, {"$set": {"operationParams": {"primitive_params": '{"dict_key": 5}'}}}
        )
        expected_calls = [call1, call2]
        self.nslcmops.update_one.assert_has_calls(expected_calls)


class TestMongoUpgrade(unittest.TestCase):
    def setUp(self):
        self.mongo = MongoUpgrade("http://fake_mongo:27017")
        self.upgrade_function = Mock()
        self.patch_function = Mock()
        db_upgrade.MONGODB_UPGRADE_FUNCTIONS = {"9": {"10": [self.upgrade_function]}}
        db_upgrade.BUG_FIXES = {1837: self.patch_function}

    def test_validate_upgrade_fail_target(self):
        valid_current = "9"
        invalid_target = "7"
        with self.assertRaises(Exception) as context:
            self.mongo._validate_upgrade(valid_current, invalid_target)
        self.assertEqual("cannot upgrade from version 9 to 7.", str(context.exception))

    def test_validate_upgrade_fail_current(self):
        invalid_current = "7"
        invalid_target = "8"
        with self.assertRaises(Exception) as context:
            self.mongo._validate_upgrade(invalid_current, invalid_target)
        self.assertEqual("cannot upgrade from 7 version.", str(context.exception))

    def test_validate_upgrade_pass(self):
        valid_current = "9"
        valid_target = "10"
        self.assertIsNone(self.mongo._validate_upgrade(valid_current, valid_target))

    @patch("db_upgrade.MongoUpgrade._validate_upgrade")
    def test_update_mongo_success(self, mock_validate):
        valid_current = "9"
        valid_target = "10"
        mock_validate.return_value = ""
        self.mongo.upgrade(valid_current, valid_target)
        self.upgrade_function.assert_called_once()

    def test_validate_apply_patch(self):
        bug_number = 1837
        self.mongo.apply_patch(bug_number)
        self.patch_function.assert_called_once()

    def test_validate_apply_patch_invalid_bug_fail(self):
        bug_number = 2
        with self.assertRaises(Exception) as context:
            self.mongo.apply_patch(bug_number)
        self.assertEqual("There is no patch for bug 2", str(context.exception))
        self.patch_function.assert_not_called()


class TestMysqlUpgrade(unittest.TestCase):
    def setUp(self):
        self.mysql = MysqlUpgrade("mysql://fake_mysql:23023")
        self.upgrade_function = Mock()
        db_upgrade.MYSQL_UPGRADE_FUNCTIONS = {"9": {"10": [self.upgrade_function]}}

    def test_validate_upgrade_mysql_fail_current(self):
        invalid_current = "7"
        invalid_target = "8"
        with self.assertRaises(Exception) as context:
            self.mysql._validate_upgrade(invalid_current, invalid_target)
        self.assertEqual("cannot upgrade from 7 version.", str(context.exception))

    def test_validate_upgrade_mysql_fail_target(self):
        valid_current = "9"
        invalid_target = "7"
        with self.assertRaises(Exception) as context:
            self.mysql._validate_upgrade(valid_current, invalid_target)
        self.assertEqual("cannot upgrade from version 9 to 7.", str(context.exception))

    def test_validate_upgrade_mysql_success(self):
        valid_current = "9"
        valid_target = "10"
        self.assertIsNone(self.mysql._validate_upgrade(valid_current, valid_target))

    @patch("db_upgrade.MysqlUpgrade._validate_upgrade")
    def test_upgrade_mysql_success(self, mock_validate):
        valid_current = "9"
        valid_target = "10"
        mock_validate.return_value = ""
        self.mysql.upgrade(valid_current, valid_target)
        self.upgrade_function.assert_called_once()
