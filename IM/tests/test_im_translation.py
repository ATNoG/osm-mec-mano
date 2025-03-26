# -*- coding: utf-8 -*-

# Copyright 2020 Whitestack, LLC
# *************************************************************
#
# This file is part of OSM common repository.
# All Rights Reserved to Whitestack, LLC
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
# contact: agarcia@whitestack.com
##

from osm_im.im_translation import translate_im_vnfd_to_sol006, translate_im_nsd_to_sol006
import unittest
import yaml

TESTS_EXAMPLES_FOLDER = 'tests/examples/'

IM_TO_SOL006_VNFD_FILES = {
    'cirros_vnfd_im.yaml': 'cirros_vnfd_sol006.yaml',
    'alternative_image_im.yaml': 'alternative_image_sol006.yaml',
    'epa_im.yaml': 'epa_sol006.yaml',
    'magma_knf_im.yaml': 'magma_knf_sol006.yaml',
    'vnfd_im.yaml': 'vnfd_sol006.yaml',
    'vepc_im.yaml': 'vepc_sol006.yaml',
    'hackfest_charmed_vnfd_im.yaml': 'hackfest_charmed_vnfd_sol006.yaml',
}

IM_TO_SOL006_NSD_FILES = {
    'cirros_nsd_im.yaml': 'cirros_nsd_sol006.yaml',
    'vepc_nsd_im.yaml': 'vepc_nsd_sol006.yaml',
    'hackfest_charmed_nsd_im.yaml': 'hackfest_charmed_nsd_sol006.yaml',
}


class TranslationTest(unittest.TestCase):
    def _sort_descriptor(self, descriptor):
        if isinstance(descriptor, dict):
            return sorted((k, self._sort_descriptor(v)) for k, v in descriptor.items())
        if isinstance(descriptor, list):
            return sorted(self._sort_descriptor(x) for x in descriptor)
        else:
            return descriptor

    def _get_descriptor_file_data_as_dict(self, descriptor_file_path):
        with open(descriptor_file_path, 'r') as descriptor_file:
            descriptor_dict = yaml.safe_load(descriptor_file.read())
        return descriptor_dict

    def test_translate_im_vnfd_to_sol006(self):
        for im_file in IM_TO_SOL006_VNFD_FILES:
            im_file_path = TESTS_EXAMPLES_FOLDER + im_file
            sol006_file_path = TESTS_EXAMPLES_FOLDER + IM_TO_SOL006_VNFD_FILES[im_file]
            im_vnfd = self._get_descriptor_file_data_as_dict(im_file_path)
            sol006_vnfd = self._get_descriptor_file_data_as_dict(sol006_file_path)

            translated_vnfd = translate_im_vnfd_to_sol006(im_vnfd)
            self.assertEqual(self._sort_descriptor(sol006_vnfd), self._sort_descriptor(translated_vnfd))

    def test_translate_im_nsd_to_sol006(self):
        for im_file in IM_TO_SOL006_NSD_FILES:
            im_file_path = TESTS_EXAMPLES_FOLDER + im_file
            sol006_file_path = TESTS_EXAMPLES_FOLDER + IM_TO_SOL006_NSD_FILES[im_file]
            im_nsd = self._get_descriptor_file_data_as_dict(im_file_path)
            sol006_nsd = self._get_descriptor_file_data_as_dict(sol006_file_path)

            translated_nsd = translate_im_nsd_to_sol006(im_nsd)
            self.assertEqual(self._sort_descriptor(sol006_nsd), self._sort_descriptor(translated_nsd))
