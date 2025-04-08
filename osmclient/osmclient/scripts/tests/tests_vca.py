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


from click.testing import CliRunner
import json
import unittest
from unittest.mock import Mock, patch
import yaml

from osmclient.cli_commands import vca


@patch("builtins.print")
@patch("osmclient.cli_commands.vca.PrettyTable")
@patch("osmclient.scripts.osm.client.Client")
@patch("osmclient.cli_commands.utils.check_client_version")
@patch("osmclient.cli_commands.vca.utils.get_project")
class TestVca(unittest.TestCase):
    def setUp(self):
        self.runner = CliRunner()
        self.ctx_obj = Mock()
        self.table = Mock()
        self.vca_data = {
            "name": "name",
            "_id": "1234",
            "_admin": {
                "detailed-status": "status",
                "operationalState": "state",
            },
        }

    def test_vca_list(
        self,
        mock_get_project,
        mock_check_client_version,
        mock_client,
        mock_pretty_table,
        mock_print,
    ):
        mock_client.return_value = self.ctx_obj
        mock_pretty_table.return_value = self.table
        mock_get_project.return_value = ("5678", "project")
        self.ctx_obj.vca.list.return_value = [self.vca_data]
        self.runner.invoke(
            vca.vca_list,
            obj=self.ctx_obj,
            args=["--filter", "somefilter"],
        )
        mock_check_client_version.assert_called()
        self.ctx_obj.vca.list.assert_called_with("somefilter")
        mock_pretty_table.assert_called_with(["Name", "Id", "Operational State"])
        self.table.add_row.assert_called_with(["name", "1234", "state"])
        mock_print.assert_called_with(self.table)

    def test_vca_list_long(
        self,
        mock_get_project,
        mock_check_client_version,
        mock_client,
        mock_pretty_table,
        mock_print,
    ):
        mock_client.return_value = self.ctx_obj
        mock_pretty_table.return_value = self.table
        mock_get_project.return_value = ("5678", "project")
        self.ctx_obj.vca.list.return_value = [self.vca_data]
        self.runner.invoke(
            vca.vca_list,
            obj=self.ctx_obj,
            args=["--filter", "somefilter", "--long"],
        )
        mock_check_client_version.assert_called()
        self.ctx_obj.vca.list.assert_called_with("somefilter")
        mock_pretty_table.assert_called_with(
            ["Name", "Id", "Project", "Operational State", "Detailed Status"]
        )
        self.table.add_row.assert_called_with(
            ["name", "1234", "project", "state", "status"]
        )
        mock_print.assert_called_with(self.table)

    def test_vca_list_literal(
        self,
        mock_get_project,
        mock_check_client_version,
        mock_client,
        mock_pretty_table,
        mock_print,
    ):
        mock_client.return_value = self.ctx_obj
        self.ctx_obj.vca.list.return_value = [self.vca_data]
        self.runner.invoke(
            vca.vca_list,
            obj=self.ctx_obj,
            args=["--literal"],
        )
        mock_check_client_version.assert_called()
        self.ctx_obj.vca.list.assert_called()
        mock_pretty_table.assert_not_called()
        self.table.add_row.assert_not_called()
        mock_print.assert_called_with(
            yaml.safe_dump([self.vca_data], indent=4, default_flow_style=False)
        )

    def test_vca_show(
        self,
        mock_get_project,
        mock_check_client_version,
        mock_client,
        mock_pretty_table,
        mock_print,
    ):
        mock_client.return_value = self.ctx_obj
        mock_pretty_table.return_value = self.table
        self.ctx_obj.vca.get.return_value = self.vca_data
        self.runner.invoke(
            vca.vca_show,
            obj=self.ctx_obj,
            args=["name"],
        )
        self.ctx_obj.vca.get.assert_called_with("name")
        mock_pretty_table.assert_called_with(["key", "attribute"])
        self.assertEqual(self.table.add_row.call_count, len(self.vca_data))
        mock_print.assert_called_with(self.table)

    def test_vca_show_literal(
        self,
        mock_get_project,
        mock_check_client_version,
        mock_client,
        mock_pretty_table,
        mock_print,
    ):
        mock_client.return_value = self.ctx_obj
        self.ctx_obj.vca.get.return_value = self.vca_data
        self.runner.invoke(
            vca.vca_show,
            obj=self.ctx_obj,
            args=["name", "--literal"],
        )
        self.ctx_obj.vca.get.assert_called_with("name")
        mock_pretty_table.assert_not_called()
        self.table.add_row.assert_not_called()
        mock_print.assert_called_with(
            yaml.safe_dump(self.vca_data, indent=4, default_flow_style=False)
        )

    def test_vca_update(
        self,
        mock_get_project,
        mock_check_client_version,
        mock_client,
        mock_pretty_table,
        mock_print,
    ):
        mock_client.return_value = self.ctx_obj
        self.runner.invoke(
            vca.vca_update,
            obj=self.ctx_obj,
            args=["name"],
        )
        mock_check_client_version.assert_called()
        self.ctx_obj.vca.update.assert_called_with("name", {})
        mock_pretty_table.assert_not_called()
        self.table.add_row.assert_not_called()
        mock_print.assert_not_called()

    def test_vca_update_with_args(
        self,
        mock_get_project,
        mock_check_client_version,
        mock_client,
        mock_pretty_table,
        mock_print,
    ):
        mock_client.return_value = self.ctx_obj
        self.runner.invoke(
            vca.vca_update,
            obj=self.ctx_obj,
            args=[
                "name",
                "--newname",
                "newname",
                "--endpoints",
                "1.2.3.4:17070",
                "--user",
                "user",
                "--secret",
                "secret",
                "--cacert",
                "cacert",
                "--lxd-cloud",
                "lxd_cloud",
                "--lxd-credentials",
                "lxd_credentials",
                "--k8s-cloud",
                "k8s_cloud",
                "--k8s-credentials",
                "k8s_credentials",
                "--description",
                "description",
                "--model-config",
                json.dumps({"juju-https-proxy": "http://squid:3128"}),
            ],
        )
        mock_check_client_version.assert_called()
        self.ctx_obj.vca.update.assert_called_with(
            "name",
            {
                "name": "newname",
                "endpoints": ["1.2.3.4:17070"],
                "user": "user",
                "secret": "secret",
                "cacert": "cacert",
                "lxd-cloud": "lxd_cloud",
                "lxd-credentials": "lxd_credentials",
                "k8s-cloud": "k8s_cloud",
                "k8s-credentials": "k8s_credentials",
                "description": "description",
                "model-config": {"juju-https-proxy": "http://squid:3128"},
            },
        )
        mock_pretty_table.assert_not_called()
        self.table.add_row.assert_not_called()
        mock_print.assert_not_called()

    def test_vca_add(
        self,
        mock_get_project,
        mock_check_client_version,
        mock_client,
        mock_pretty_table,
        mock_print,
    ):
        mock_client.return_value = self.ctx_obj
        self.runner.invoke(
            vca.vca_add,
            obj=self.ctx_obj,
            args=[
                "name",
                "--endpoints",
                "1.2.3.4:17070",
                "--user",
                "user",
                "--secret",
                "secret",
                "--cacert",
                "cacert",
                "--lxd-cloud",
                "lxd_cloud",
                "--lxd-credentials",
                "lxd_credentials",
                "--k8s-cloud",
                "k8s_cloud",
                "--k8s-credentials",
                "k8s_credentials",
                "--description",
                "description",
                "--model-config",
                json.dumps({"juju-https-proxy": "http://squid:3128"}),
            ],
        )
        mock_check_client_version.assert_called()
        self.ctx_obj.vca.create.assert_called_with(
            "name",
            {
                "name": "name",
                "endpoints": ["1.2.3.4:17070"],
                "user": "user",
                "secret": "secret",
                "cacert": "cacert",
                "lxd-cloud": "lxd_cloud",
                "lxd-credentials": "lxd_credentials",
                "k8s-cloud": "k8s_cloud",
                "k8s-credentials": "k8s_credentials",
                "description": "description",
                "model-config": {"juju-https-proxy": "http://squid:3128"},
            },
        )
        mock_pretty_table.assert_not_called()
        self.table.add_row.assert_not_called()
        mock_print.assert_not_called()

    def test_vca_delete(
        self,
        mock_get_project,
        mock_check_client_version,
        mock_client,
        mock_pretty_table,
        mock_print,
    ):
        mock_client.return_value = self.ctx_obj
        self.runner.invoke(
            vca.vca_delete,
            obj=self.ctx_obj,
            args=["name"],
        )
        mock_check_client_version.assert_called()
        self.ctx_obj.vca.delete.assert_called_with("name", force=False)
        mock_pretty_table.assert_not_called()
        self.table.add_row.assert_not_called()
        mock_print.assert_not_called()

    def test_load(
        self,
        mock_get_project,
        mock_check_client_version,
        mock_client,
        mock_pretty_table,
        mock_print,
    ):
        data = vca.load(json.dumps({"juju-https-proxy": "http://squid:3128"}))
        self.assertEqual(data, {"juju-https-proxy": "http://squid:3128"})
