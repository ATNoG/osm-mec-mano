#!/bin/bash
#
#   Copyright 2020 ETSI
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
#

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage $0 <TAG> <GIT_USER> [<GIT_PASSWORD>]"
    echo "Example: $0 v18.0.1 garciadeblas"
    echo "When <GIT_PASSWORD> is provided, it will be used for git https authentication. Otherwise, ssh authentication will be used."
    exit 1
fi

TAG="$1"
GIT_USER="$2"
GIT_PASSWORD="${3:-}"

BRANCH_NAME="v$(echo $TAG | grep -oE '[0-9]+\.[0-9]+')"

declare -A branch_release_map=(
    ["v14.0"]="FOURTEEN"
    ["v15.0"]="FIFTEEN"
    ["v16.0"]="SIXTEEN"
    ["v17.0"]="SEVENTEEN"
    ["v18.0"]="EIGHTEEN"
    ["v19.0"]="NINETEEN"
    ["v20.0"]="TWENTY"
    ["v21.0"]="TWENTYONE"
    ["v22.0"]="TWENTYTWO"
    ["v23.0"]="TWENTYTHREE"
)

RELEASE_NAME="${branch_release_map[$BRANCH_NAME]}"
if [ -z "$RELEASE_NAME" ]; then
    echo "Unknown branch name: $BRANCH_NAME"
    exit 1
fi
tag_header="OSM Release $RELEASE_NAME:"
tag_message="$tag_header version $TAG"

declare -A branch_module_map=(
    ["v14.0"]="common devops IM LCM MON N2VC NBI NG-UI NG-SA osmclient RO PLA POL SOL003 SOL005 tests"
    ["v15.0"]="common devops IM LCM MON N2VC NBI NG-UI NG-SA osmclient RO PLA POL SOL003 SOL005 tests"
    ["v16.0"]="common devops IM LCM MON N2VC NBI NG-UI NG-SA osmclient RO PLA POL SOL003 SOL005 tests"
    ["v17.0"]="common devops IM LCM MON N2VC NBI NG-UI NG-SA osmclient RO PLA POL SOL003 SOL005 tests"
    ["v18.0"]="common devops IM LCM MON NBI NG-UI NG-SA osmclient RO SOL003 SOL005 tests"
    ["v19.0"]="common devops IM LCM MON NBI NG-UI NG-SA osmclient RO SOL003 SOL005 tests"
    ["v20.0"]="common devops IM LCM MON NBI NG-UI NG-SA osmclient RO SOL003 SOL005 tests"
    ["v21.0"]="common devops IM LCM MON NBI NG-UI NG-SA osmclient RO SOL003 SOL005 tests"
    ["v22.0"]="common devops IM LCM MON NBI NG-UI NG-SA osmclient RO SOL003 SOL005 tests"
    ["v23.0"]="common devops IM LCM MON NBI NG-UI NG-SA osmclient RO SOL003 SOL005 tests"
)
MODULE_LIST="${branch_module_map[$BRANCH_NAME]}"
if [ -z "$MODULE_LIST" ]; then
    echo "Unknown branch name: $BRANCH_NAME"
    exit 1
fi


BASE_FOLDER=$(mktemp -d --tmpdir change-chart-version.XXXXXX)
pushd $BASE_FOLDER

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

for i in ${MODULE_LIST}; do
    echo "Cloning $i repo"
    REPO_URL="${REPO_BASE_URL}/${i}"
    if [ -n "$GIT_PASSWORD" ]; then
        echo "Using https authentication"
        GIT_USERNAME="${GIT_USER}" GIT_ASKPASS=~/git-creds.sh git clone "${REPO_URL}"
    else
        echo "Using ssh authentication"
        git clone "${REPO_URL}"
    fi
    git -C $i checkout $BRANCH_NAME || ! echo "$BRANCH_NAME was not found in $i repo" || continue
    git -C $i pull --rebase
    echo "Creating new tag $TAG in repo $i associated to branch $BRANCH_NAME"
    git -C $i tag -a $TAG -m"$tag_message"
    echo "Pushing changes to $i repo"
    git -C $i push origin $TAG --follow-tags
    sleep 2
done

popd

exit 0
