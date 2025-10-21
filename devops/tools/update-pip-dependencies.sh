#!/bin/bash
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

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
    echo "Usage $0 <BRANCH> <GIT_USER> [<DO_PUSH>] [<GIT_PASSWORD>]"
    echo "Example: $0 v18.0 garciadeblas false"
    echo "When <GIT_PASSWORD> is provided, it will be used for git https authentication. Otherwise, ssh authentication will be used."
    exit 1
fi

set -e -o pipefail

BRANCH_NAME="$1"
GIT_USER="$2"
DO_PUSH="${3:-"true"}"
GIT_PASSWORD="${4:-}"

declare -A branch_module_map=(
    ["v14.0"]="common IM LCM MON N2VC NBI NG-SA osmclient RO PLA POL tests"
    ["v15.0"]="common IM LCM MON N2VC NBI NG-SA osmclient RO PLA POL tests"
    ["v16.0"]="common IM LCM MON N2VC NBI NG-SA osmclient RO PLA POL tests"
    ["v17.0"]="common IM LCM MON N2VC NBI NG-SA osmclient RO PLA POL tests"
    ["v18.0"]="common IM LCM MON NBI NG-SA osmclient RO tests"
    ["v19.0"]="common IM LCM MON NBI NG-SA osmclient RO tests"
    ["v20.0"]="common IM LCM MON NBI NG-SA osmclient RO tests"
    ["v21.0"]="common IM LCM MON NBI NG-SA osmclient RO tests"
    ["v22.0"]="common IM LCM MON NBI NG-SA osmclient RO tests"
    ["v23.0"]="common IM LCM MON NBI NG-SA osmclient RO tests"
    ["master"]="common IM LCM MON NBI NG-SA osmclient RO tests"
)
MODULE_LIST="${branch_module_map[$BRANCH_NAME]}"
if [ -z "$MODULE_LIST" ]; then
    echo "Unknown branch name: $BRANCH_NAME"
    exit 1
fi

# Create a temporary folder
BASE_FOLDER=$(mktemp -d --tmpdir update-pip-dependencies.XXXXXX)
pushd ${BASE_FOLDER}
echo "Using temporary directory: ${BASE_FOLDER}"

if [ -n "$GIT_PASSWORD" ]; then
    REPO_BASE_URL="https://${GIT_USER}@osm.etsi.org/gerrit/a/osm"
    # Follow recommendation for user auth with git using a script git-creds.sh
    cat << "EOF" > "${HOME}/git-creds.sh"
#!/bin/sh
if echo "$1" | grep -q '^Password'; then
  echo "${GIT_PASSWORD}"
else
  echo "${GIT_USER}"
fi
exit 0
EOF
    chmod +x "${HOME}/git-creds.sh"
else
    REPO_BASE_URL="ssh://${GIT_USER}@osm.etsi.org:29418/osm"
fi

echo "Updating pip dependencies"
for i in ${MODULE_LIST}; do
    echo "Updating pip dependencies for $i"
    REPO_DIR="${BASE_FOLDER}/$i"
    REPO_URL="${REPO_BASE_URL}/${i}"
    echo "Cloning $i repo"
    if [ -n "$GIT_PASSWORD" ]; then
        echo "Using https authentication"
        GIT_USERNAME="${GIT_USER}" GIT_ASKPASS=~/git-creds.sh git clone "${REPO_URL}"
    else
        echo "Using ssh authentication"
        git clone "${REPO_URL}"
    fi
    pushd "$REPO_DIR"
    git checkout $BRANCH_NAME
    git pull --rebase
    tox -e pip-compile
    git add -u
    # Only commit if there are staged changes
    if ! git diff --cached --quiet; then
        git show HEAD --stat
        git diff HEAD^ > "${BASE_FOLDER}/$i.diff"
        echo "===================" | tee -a "${BASE_FOLDER}/all.diff"
        echo "Showing diff for $i" | tee -a "${BASE_FOLDER}/all.diff"
        echo "===================" | tee -a "${BASE_FOLDER}/all.diff"
        git diff HEAD^ | tee -a "${BASE_FOLDER}/all.diff"
        if [ "$DO_PUSH" == "true" ]; then
            echo "Pushing changes for $i"
            if [ -n "$GIT_PASSWORD" ]; then
                echo "Using https authentication"
                GIT_USERNAME="${GIT_USER}" GIT_ASKPASS=~/git-creds.sh git push origin $BRANCH_NAME
            else
                echo "Using ssh authentication"
                git push origin $BRANCH_NAME
            fi
        fi
    else
        echo "No changes to commit for $i"
    fi
    popd
done

popd

echo "All diffs saved in ${BASE_FOLDER}/all.diff"

exit 0
