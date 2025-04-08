# Copyright 2021 ATOS.
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

import unittest
import shutil
from pathlib import Path

from osmclient.sol005.osmrepo import OSMRepo


class TestOSMRepo(unittest.TestCase):
    def setUp(self):
        self.repo = OSMRepo()

    def test_init_repo_structure(self):
        # TODO: Mock filesystem after refactoring from os to pathlib
        # TODO: Mock OSM IM repo if possible
        repo_base = Path(__file__).parent / Path("test_repo")
        expected_index_file_path = repo_base / Path("index.yaml")
        self.repo.init_directory(str(repo_base))
        self.assertTrue(expected_index_file_path.exists())
        shutil.rmtree(expected_index_file_path.parent)
