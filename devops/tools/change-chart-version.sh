#!/bin/bash
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
  echo "Usage: $0 <NEW_VERSION> <GIT_USER> [<GIT_PASSWORD>]"
  echo "    Example: $0 16.0.0 garciadeblas"
  echo "    Example: $0 15.0.7 vegall"
  echo "When <GIT_PASSWORD> is provided, it will be used for git https authentication. Otherwise, ssh authentication will be used."
  exit 1
fi

NEW_VERSION="$1"
GIT_USER="$2"
GIT_PASSWORD="${3:-}"

BRANCH_NAME="v$(echo $NEW_VERSION | grep -oE '[0-9]+\.[0-9]+')"

BASE_FOLDER=$(mktemp -d --tmpdir change-chart-version.XXXXXX)
pushd $BASE_FOLDER

if [ -n "$GIT_PASSWORD" ]; then
    REPO_URL="https://${GIT_USER}@osm.etsi.org/gerrit/a/osm/devops"
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
    REPO_URL="ssh://${GIT_USER}@osm.etsi.org:29418/osm/devops"
fi

echo "Cloning devops repo"
if [ -n "$GIT_PASSWORD" ]; then
    echo "Using https authentication"
    GIT_USERNAME="${GIT_USER}" GIT_ASKPASS=~/git-creds.sh git clone "${REPO_URL}"
else
    echo "Using ssh authentication"
    git clone "${REPO_URL}"
fi
cd "devops"
curl https://osm.etsi.org/gerrit/tools/hooks/commit-msg > .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg

git checkout $BRANCH_NAME
sed -i -E "0,/^version: .*/s//version: \"$NEW_VERSION\"/" installers/helm/osm/Chart.yaml
sed -i -E "0,/^appVersion: .*/s//appVersion: \"$NEW_VERSION\"/" installers/helm/osm/Chart.yaml

git add installers/helm/osm/Chart.yaml
git commit -s -m "Update chart version version to $NEW_VERSION"

echo "Pushing changes to devops repo"
if [ -n "$GIT_PASSWORD" ]; then
    echo "Using https authentication"
    GIT_USERNAME="${GIT_USER}" GIT_ASKPASS=~/git-creds.sh git push origin $BRANCH_NAME
else
    echo "Using ssh authentication"
    git push origin $BRANCH_NAME
fi

commit=$(git show --summary | grep commit | awk '{print $2}')
echo "The commit is $commit"
cd ..
rm -rf devops

popd
