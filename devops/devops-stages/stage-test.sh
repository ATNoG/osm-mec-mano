#!/bin/sh
#   Copyright 2021 Canonical Ltd.
#   Copyright ETSI
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

set -eu

# Download helm chart dependencies
helm dependency update installers/helm/osm

# Execute linting test for OSM helm chart
helm lint installers/helm/osm

# Execute datree test for OSM helm chart
# helm datree test installers/helm/osm --verbose

