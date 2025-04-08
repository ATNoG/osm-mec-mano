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
from unittest.mock import Mock, patch, mock_open
from click.testing import CliRunner
from osmclient.cli_commands import vim


@patch("osmclient.cli_commands.utils.check_client_version")
@patch("osmclient.scripts.osm.client.Client")
@patch("osmclient.cli_commands.utils.create_config")
class TestVim(unittest.TestCase):
    def setUp(self):
        self.runner = CliRunner()
        self.ctx_obj = Mock()

    def test_vim_create_ca_cert(
        self,
        mock_create_config,
        mock_client,
        mock_check_client_version,
    ):
        mock_client.return_value = self.ctx_obj
        mock_create_config.return_value = {"ca_cert": "/home/ubuntu/.ssh/id_rsa.pub"}
        vim_config = mock_create_config.return_value
        with patch("builtins.open", mock_open(read_data="test")):
            self.runner.invoke(
                vim.vim_create,
                obj=self.ctx_obj,
                args=[
                    "--name",
                    "vim1",
                    "--user",
                    "user1",
                    "--password",
                    "pass",
                    "--auth_url",
                    "http://test",
                    "--tenant",
                    "tenant1",
                    "--config",
                    json.dumps({"ca_cert": "/home/ubuntu/.ssh/id_rsa.pub"}),
                    "--account_type",
                    "openstack",
                ],
            )

        mock_create_config.assert_called()
        assert vim_config["ca_cert_content"] == "test"

        self.ctx_obj.vim.create.assert_called_with(
            "vim1",
            {
                "vim-username": "user1",
                "vim-password": "pass",
                "vim-url": "http://test",
                "vim-tenant-name": "tenant1",
                "vim-type": "openstack",
                "description": None,
            },
            {"ca_cert_content": "test"},
            None,
            None,
            wait=False,
        )

    def test_vim_create_no_config(
        self,
        mock_create_config,
        mock_client,
        mock_check_client_version,
    ):
        mock_client.return_value = self.ctx_obj
        mock_create_config.return_value = {}

        with patch("builtins.open", mock_open(read_data="test")):
            self.runner.invoke(
                vim.vim_create,
                obj=self.ctx_obj,
                args=[
                    "--name",
                    "vim1",
                    "--user",
                    "user1",
                    "--password",
                    "pass",
                    "--auth_url",
                    "http://test",
                    "--tenant",
                    "tenant1",
                    "--account_type",
                    "openstack",
                ],
            )
        mock_check_client_version.assert_not_called()
        mock_create_config.assert_called()

        self.ctx_obj.vim.create.assert_called_with(
            "vim1",
            {
                "vim-username": "user1",
                "vim-password": "pass",
                "vim-url": "http://test",
                "vim-tenant-name": "tenant1",
                "vim-type": "openstack",
                "description": None,
            },
            {},
            None,
            None,
            wait=False,
        )

    def test_vim_create_sdn(
        self,
        mock_create_config,
        mock_client,
        mock_check_client_version,
    ):
        mock_client.return_value = self.ctx_obj
        mock_create_config.return_value = {}

        with patch("builtins.open", mock_open(read_data="test")):
            self.runner.invoke(
                vim.vim_create,
                obj=self.ctx_obj,
                args=[
                    "--name",
                    "vim1",
                    "--user",
                    "user1",
                    "--password",
                    "pass",
                    "--auth_url",
                    "http://test",
                    "--tenant",
                    "tenant1",
                    "--account_type",
                    "openstack",
                    "--sdn_controller",
                    "controller",
                    "--sdn_port_mapping",
                    "port-map",
                ],
            )
        mock_check_client_version.call_count == 2
        mock_create_config.assert_called()

        self.ctx_obj.vim.create.assert_called_with(
            "vim1",
            {
                "vim-username": "user1",
                "vim-password": "pass",
                "vim-url": "http://test",
                "vim-tenant-name": "tenant1",
                "vim-type": "openstack",
                "description": None,
            },
            {},
            "controller",
            "port-map",
            wait=False,
        )

    def test_vim_update_ca_cert(
        self,
        mock_create_config,
        mock_client,
        mock_check_client_version,
    ):
        mock_client.return_value = self.ctx_obj
        mock_create_config.return_value = {"ca_cert": "/home/ubuntu/.ssh/id_rsa.pub"}
        vim_config = mock_create_config.return_value
        with patch("builtins.open", mock_open(read_data="test")):
            self.runner.invoke(
                vim.vim_update,
                obj=self.ctx_obj,
                args=[
                    "vim1",
                    "--config",
                    json.dumps({"ca_cert": "/home/ubuntu/.ssh/id_rsa.pub"}),
                ],
            )

        mock_check_client_version.assert_called()
        mock_create_config.assert_called()
        assert vim_config["ca_cert_content"] == "test"

        self.ctx_obj.vim.update.assert_called_with(
            "vim1",
            {},
            {"ca_cert_content": "test"},
            None,
            None,
            wait=False,
        )

    def test_vim_update_no_config(
        self,
        mock_create_config,
        mock_client,
        mock_check_client_version,
    ):
        mock_client.return_value = self.ctx_obj

        with patch("builtins.open", mock_open(read_data="test")):
            self.runner.invoke(
                vim.vim_update,
                obj=self.ctx_obj,
                args=[
                    "vim1",
                    "--password",
                    "passwd",
                ],
            )
        mock_check_client_version.assert_called()
        mock_create_config.assert_not_called()

        self.ctx_obj.vim.update.assert_called_with(
            "vim1",
            {
                "vim_password": "passwd",
            },
            None,
            None,
            None,
            wait=False,
        )

    def test_vim_update_sdn(
        self,
        mock_create_config,
        mock_client,
        mock_check_client_version,
    ):
        mock_client.return_value = self.ctx_obj
        mock_create_config.return_value = {}

        with patch("builtins.open", mock_open(read_data="test")):
            self.runner.invoke(
                vim.vim_update,
                obj=self.ctx_obj,
                args=[
                    "vim1",
                    "--sdn_controller",
                    "controller",
                    "--sdn_port_mapping",
                    "port-map",
                ],
            )
        mock_check_client_version.assert_called()
        mock_create_config.assert_not_called()

        self.ctx_obj.vim.update.assert_called_with(
            "vim1",
            {},
            None,
            "controller",
            "port-map",
            wait=False,
        )
