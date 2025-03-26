#  Copyright 2020 Whitestack LLC
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
#  implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

from osm_im.validation import Validation
import unittest

TESTS_EXAMPLES_FOLDER = 'tests/examples/'

VNFD_FILES = [
    'alternative_image_sol006.yaml',
    'cirros_vnfd_sol006.yaml',
    'epa_sol006.yaml',
    'etsi_complex_vnfd_sol006.yaml',
    'hackfest_charmed_vnfd_sol006.yaml',
    'magma_knf_sol006.yaml',
    'vepc_sol006.yaml',
    'vnfd_sol006.yaml',
    'vnfd_sol006_k8s_scale.yaml',
]

NSD_FILES = [
    'cirros_nsd_sol006.yaml',
    'etsi_nsd_sol006.yaml',
    'hackfest_charmed_nsd_sol006.yaml',
    'vepc_nsd_sol006.yaml'
]

class ValidationTest(unittest.TestCase):

    def test_descriptor_validation_of_etsi_nfv_vnfd(self):
        for file in VNFD_FILES:
            file_path = TESTS_EXAMPLES_FOLDER + file
            with open(file_path, 'r') as vnfd_file:
                vnfd_file_content = vnfd_file.read()
            Validation().descriptor_validation(vnfd_file_content)

    def test_descriptor_validation_of_etsi_nfv_nsd(self):
        for file in NSD_FILES:
            file_path = TESTS_EXAMPLES_FOLDER + file
            with open(file_path, 'r') as nsd_file:
                nsd_file_content = nsd_file.read()
            Validation().descriptor_validation(nsd_file_content)
