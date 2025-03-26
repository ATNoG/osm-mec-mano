# -*- coding: utf-8 -*-

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

import yaml
import importlib
from osm_im.vnfd import vnfd as vnfd_im
from osm_im.nsd import nsd as nsd_im
from osm_im.nst import nst as nst_im
from osm_im import etsi_nfv_vnfd, etsi_nfv_nsd
from pyangbind.lib.serialise import pybindJSONDecoder
import pyangbind.lib.pybindJSON as pybindJSON

class ValidationException(Exception):
    pass

class Validation:

    def pyangbind_validation(self, item, data, force=False):
        '''
        item: vnfd, nst, nsd
        data: dict object loaded from the descriptor file
        force: True to skip unknown fields in the descriptor
        '''
        if item == "vnfd":
            myobj = vnfd_im()
        elif item == "nsd":
            myobj = nsd_im()
        elif item == "nst":
            myobj = nst_im()
        elif item == "etsi_nfv_vnfd":
            myobj = etsi_nfv_vnfd.etsi_nfv_vnfd()
        elif item == "etsi_nfv_nsd":
            myobj = etsi_nfv_nsd.etsi_nfv_nsd()
        else:
            raise ValidationException("Not possible to validate '{}' item".format(item))

        try:
            pybindJSONDecoder.load_ietf_json(data, None, None, obj=myobj,
                                             path_helper=True, skip_unknown=force)
            out = pybindJSON.dumps(myobj, mode="ietf")
            desc_out = yaml.safe_load(out)
            return desc_out
        except Exception as e:
            raise ValidationException("Error in pyangbind validation: {}".format(str(e)))

    def yaml_validation(self, descriptor):
        try:
            data = yaml.safe_load(descriptor)
        except Exception as e:
            raise ValidationException("Error in YAML validation. Not a proper YAML file: {}".format(e))
        if 'vnfd:vnfd-catalog' in data or 'vnfd-catalog' in data:
            item = "vnfd"
        elif 'nsd:nsd-catalog' in data or 'nsd-catalog' in data:
            item = "nsd"
        elif 'nst' in data:
            item = "nst"
        elif 'vnfd' in data:
            item = "etsi_nfv_vnfd"
        elif 'nsd' in data:
            item = "etsi_nfv_nsd"
        else:
            raise ValidationException("Error in YAML validation. Not possible to determine the type of descriptor in the first line. Expected values: vnfd:vnfd-catalog, vnfd-catalog, nsd:nsd-catalog, nsd-catalog, nst")

        return item, data

    def descriptor_validation(self, descriptor):
        item, data = self.yaml_validation(descriptor)
        self.pyangbind_validation(item, data)

