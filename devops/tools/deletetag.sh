#!/bin/bash
#
#   Copyright ETSI Contributors and Others
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
if [ $# -ne 2 ]; then
    echo "Usage $0 <repo> <tag>"
    echo "Example: $0 all v11.0.1"
    echo "Example: $0 devops v11.0.3"
    exit 1
fi

TAG="$2"
tag_header="OSM Release TWO:"
tag_message="$tag_header version $TAG"

modules="common devops IM LCM MON N2VC NBI NG-UI NG-SA osmclient RO SOL003 SOL005 tests"
list=""
for i in $modules; do
    if [ "$1" == "$i" -o "$1" == "all" ]; then
        list="$1"
        break
    fi
done

[ "$1" == "all" ] && list=$modules

if [ -z "$list" ]; then
    echo "Repo must be one of these: $modules all"
    exit 1
fi

for i in $list; do
    echo $i
    if [ ! -d $i ]; then
        git clone ssh://$USER@osm.etsi.org:29418/osm/$i
    fi
    git -C $i fetch
    echo "Deleting tag $TAG in repo $i"
    git -C $i tag -d $TAG
    git -C $i push origin :refs/tags/$TAG
    sleep 2
done

exit 0

