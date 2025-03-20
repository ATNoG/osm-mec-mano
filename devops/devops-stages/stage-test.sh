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

CURRENT_DIR=`pwd`

# Execute tests for charms
CHARM_PATH="./installers/charm"
NEW_CHARMS_NAMES="osm-keystone osm-lcm osm-mon osm-nbi osm-ng-ui osm-pol osm-ro vca-integrator-operator"
OLD_CHARMS_NAMES="prometheus grafana"
LOCAL_GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
GERRIT_BRANCH=${GERRIT_BRANCH:-${LOCAL_GIT_BRANCH}}
for charm in $NEW_CHARMS_NAMES; do
    if [ $(git diff --name-only "origin/${GERRIT_BRANCH}" -- "installers/charm/${charm}" | wc -l) -ne 0 ]; then
        echo "Running tox for ${charm}"
        cd "${CHARM_PATH}/${charm}"
        TOX_PARALLEL_NO_SPINNER=1 tox -e lint,unit --parallel=auto
        cd "${CURRENT_DIR}"
    fi
done
for charm in $OLD_CHARMS_NAMES; do
    if [ $(git diff --name-only "origin/${GERRIT_BRANCH}" -- "installers/charm/${charm}" | wc -l) -ne 0 ]; then
        echo "Running tox for ${charm}"
        cd "${CHARM_PATH}/${charm}"
        TOX_PARALLEL_NO_SPINNER=1 tox --parallel=auto
        cd "${CURRENT_DIR}"
    fi
done

# Download helm chart dependencies
helm dependency update installers/helm/osm

# Execute linting test for OSM helm chart
helm lint installers/helm/osm

# Execute datree test for OSM helm chart
# helm datree test installers/helm/osm --verbose

