# Copyright 2021 Canonical Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#     Unless required by applicable law or agreed to in writing, software
#     distributed under the License is distributed on an "AS IS" BASIS,
#     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#     See the License for the specific language governing permissions and
#     limitations under the License.

import json
import unittest
from unittest.mock import Mock, patch


from osmclient.common.exceptions import ClientException, NotFound
from osmclient.sol005.vca import VCA


class TestVca(unittest.TestCase):
    def setUp(self):
        self.vca = VCA(Mock(), Mock())
        self.vca_data = {
            "name": "name",
            "endpoints": ["127.0.0.1:17070"],
            "user": "user",
            "secret": "secret",
            "cacert": "cacert",
            "lxd-cloud": "lxd_cloud",
            "lxd-credentials": "lxd_credentials",
            "k8s-cloud": "k8s_cloud",
            "k8s-credentials": "k8s_credentials",
            "description": "description",
            "model-config": {},
        }

    @patch("builtins.print")
    def test_create_success(self, mock_print):
        self.vca._http.post_cmd.return_value = (200, '{"id": "1234"}')
        self.vca.create("vca_name", self.vca_data)
        self.vca._client.get_token.assert_called()
        self.vca._http.post_cmd.assert_called()
        mock_print.assert_called_with("1234")

    @patch("builtins.print")
    def test_create_missing_id(self, mock_print):
        self.vca._http.post_cmd.return_value = (404, None)
        with self.assertRaises(ClientException):
            self.vca.create("vca_name", self.vca_data)
        self.vca._client.get_token.assert_called()
        self.vca._http.post_cmd.assert_called()
        mock_print.assert_not_called()

    def test_update_success(self):
        self.vca.get = Mock()
        self.vca.get.return_value = {"_id": "1234"}
        self.vca.update("vca_name", self.vca_data)
        self.vca._http.patch_cmd.assert_called_with(
            endpoint="/admin/v1/vca/1234", postfields_dict=self.vca_data
        )

    def test_get_id_sucess(self):
        self.vca_data.update({"_id": "1234"})
        self.vca.list = Mock()
        self.vca.list.return_value = [self.vca_data]
        vca_id = self.vca.get_id("name")
        self.assertEqual(vca_id, "1234")

    def test_get_id_not_found(self):
        self.vca.list = Mock()
        self.vca.list.return_value = []
        with self.assertRaises(NotFound):
            self.vca.get_id("name")

    @patch("osmclient.sol005.vca.utils")
    @patch("builtins.print")
    def test_delete_success_202(self, mock_print, mock_utils):
        mock_utils.validate_uuid4.return_value = False
        self.vca.get_id = Mock()
        self.vca.get_id.return_value = "1234"
        self.vca._http.delete_cmd.return_value = (202, None)
        self.vca.delete("vca_name")
        self.vca._client.get_token.assert_called()
        self.vca._http.delete_cmd.assert_called_with("/admin/v1/vca/1234")
        mock_print.assert_called_with("Deletion in progress")

    @patch("osmclient.sol005.vca.utils")
    @patch("builtins.print")
    def test_delete_success_204(self, mock_print, mock_utils):
        mock_utils.validate_uuid4.return_value = False
        self.vca.get_id = Mock()
        self.vca.get_id.return_value = "1234"
        self.vca._http.delete_cmd.return_value = (204, None)
        self.vca.delete("vca_name", force=True)
        self.vca._client.get_token.assert_called()
        self.vca._http.delete_cmd.assert_called_with("/admin/v1/vca/1234?FORCE=True")
        mock_print.assert_called_with("Deleted")

    @patch("osmclient.sol005.vca.utils")
    @patch("builtins.print")
    def test_delete_success_404(self, mock_print, mock_utils):
        mock_utils.validate_uuid4.return_value = False
        self.vca.get_id = Mock()
        self.vca.get_id.return_value = "1234"
        self.vca._http.delete_cmd.return_value = (404, "Not found")
        with self.assertRaises(ClientException):
            self.vca.delete("vca_name")
        self.vca._client.get_token.assert_called()
        self.vca._http.delete_cmd.assert_called_with("/admin/v1/vca/1234")
        mock_print.assert_not_called()

    def test_list_success(self):
        self.vca._http.get2_cmd.return_value = (None, '[{"_id": "1234"}]')
        vca_list = self.vca.list("my_filter")
        self.vca._client.get_token.assert_called()
        self.vca._http.get2_cmd.assert_called_with("/admin/v1/vca?my_filter")
        self.assertEqual(vca_list, [{"_id": "1234"}])

    def test_list_no_response(self):
        self.vca._http.get2_cmd.return_value = (None, None)
        vca_list = self.vca.list()
        self.vca._client.get_token.assert_called()
        self.vca._http.get2_cmd.assert_called_with("/admin/v1/vca")
        self.assertEqual(vca_list, [])

    @patch("osmclient.sol005.vca.utils")
    def test_get_success(self, mock_utils):
        self.vca_data.update({"_id": "1234"})
        mock_utils.validate_uuid4.return_value = False
        self.vca.get_id = Mock()
        self.vca.get_id.return_value = "1234"
        self.vca._http.get2_cmd.return_value = (404, json.dumps(self.vca_data))
        vca = self.vca.get("vca_name")
        self.vca._client.get_token.assert_called()
        self.vca._http.get2_cmd.assert_called_with("/admin/v1/vca/1234")
        self.assertEqual(vca, self.vca_data)

    @patch("osmclient.sol005.vca.utils")
    def test_get_client_exception(self, mock_utils):
        mock_utils.validate_uuid4.return_value = False
        self.vca.get_id = Mock()
        self.vca.get_id.return_value = "1234"
        self.vca._http.get2_cmd.return_value = (404, json.dumps({}))
        with self.assertRaises(ClientException):
            self.vca.get("vca_name")
        self.vca._client.get_token.assert_called()
        self.vca._http.get2_cmd.assert_called_with("/admin/v1/vca/1234")

    @patch("osmclient.sol005.vca.utils")
    def test_get_not_exception(self, mock_utils):
        mock_utils.validate_uuid4.return_value = False
        self.vca.get_id = Mock()
        self.vca.get_id.return_value = "1234"
        self.vca._http.get2_cmd.side_effect = NotFound()
        with self.assertRaises(NotFound):
            self.vca.get("vca_name")
        self.vca._client.get_token.assert_called()
        self.vca._http.get2_cmd.assert_called_with("/admin/v1/vca/1234")
