#######################################################################################
# Copyright ETSI Contributors and Others.
#
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
#######################################################################################

import pytest
from ops.testing import Harness
from pytest_mock import MockerFixture

from charm import VcaIntegratorCharm


@pytest.fixture
def harness():
    osm_vca_integrator_harness = Harness(VcaIntegratorCharm)
    osm_vca_integrator_harness.begin()
    yield osm_vca_integrator_harness
    osm_vca_integrator_harness.cleanup()


def test_on_config_changed(mocker: MockerFixture, harness: Harness):
    pass
