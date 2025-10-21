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

if [ $# -lt 2 ]; then
    echo "Usage $0 <branch> <from_tag> [ <to_tag> ]"
    echo "  It will list all the changes in branch <branch> from <from_tag> to <to_tag>."
    echo "  If <to_tag> is not provided, HEAD is used. This is useful to get all changes from a specific tag to the tip of the branch."
    echo "  Examples:"
    echo "    $0 v11.0 v11.0.0"
    echo "    $0 v10.0 v10.0"
    echo "    $0 v10.0 v10.0.3"
    echo "    $0 v10.0 v10.0.2 v10.0.3"
    exit 1
fi

BRANCH="$1"
FROM_REF="$2"
TO_REF="${3-HEAD}"

OSM_CHANGES_FOLDER="$(mktemp -d -q --tmpdir "osmchanges.XXXXXX")"
echo "Changes in branch ${BRANCH} from ${FROM_REF} to ${TO_REF} stored in ${OSM_CHANGES_FOLDER}"

#trap 'rm -rf "${OSM_CHANGES_FOLDER}"' EXIT

echo "-----------------------------------------" > "${OSM_CHANGES_FOLDER}/osm_changes-${BRANCH}-from${FROM_REF}-to${TO_REF}.log"

modules="common devops IM LCM MON N2VC NBI NG-SA NG-UI osmclient RO SOL003 SOL005 tests"
for repo in $modules; do
    echo ${repo}
    git -C ${OSM_CHANGES_FOLDER} clone "https://osm.etsi.org/gerrit/osm/${repo}"
    git -C ${OSM_CHANGES_FOLDER}/$repo checkout ${BRANCH}

    # Print changes in the module changelog
    git -C ${OSM_CHANGES_FOLDER}/$repo log --pretty=format:"%C(yellow)%h %Cblue%ad %Cgreen%>(13,trunc)%an %Creset%s" --date=short ${FROM_REF}..${TO_REF} > "${OSM_CHANGES_FOLDER}/${repo}_changes-${BRANCH}-from${FROM_REF}-to${TO_REF}.log"
    echo >> "${OSM_CHANGES_FOLDER}/${repo}_changes-${BRANCH}-from${FROM_REF}-to${TO_REF}.log"

    # Print changes in the global changelog
    echo ${repo} >> "${OSM_CHANGES_FOLDER}/osm_changes-${BRANCH}-from${FROM_REF}-to${TO_REF}.log"
    git -C ${OSM_CHANGES_FOLDER}/$repo log --pretty=format:"%C(yellow)%h %Cblue%ad %Cgreen%>(13,trunc)%an %Creset%s" --date=short ${FROM_REF}..${TO_REF} >> "${OSM_CHANGES_FOLDER}/osm_changes-${BRANCH}-from${FROM_REF}-to${TO_REF}.log"
    echo >> "${OSM_CHANGES_FOLDER}/osm_changes-${BRANCH}-from${FROM_REF}-to${TO_REF}.log"
    echo "-----------------------------------------" >> "${OSM_CHANGES_FOLDER}/osm_changes-${BRANCH}-from${FROM_REF}-to${TO_REF}.log"
done

echo
echo "Changes in branch ${BRANCH} from ${FROM_REF} to ${TO_REF} stored in ${OSM_CHANGES_FOLDER}"
echo "All changes can be found in ${OSM_CHANGES_FOLDER}/osm_changes-${BRANCH}-from${FROM_REF}-to${TO_REF}.log"

