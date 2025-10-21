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

if [ $# -ne 3 ]; then
    echo "Usage $0 <repo> <branch> <user>"
    echo "Example: $0 all v8.0 beierlm"
    echo "Example: $0 devops v8.0 beierlm"
    exit 1
fi

BRANCH="$2"
USER="$3"
tag_message="Start of $BRANCH"

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
    echo "============================================="
    echo $i
    if [ ! -d $i ]; then
        git clone ssh://$USER@osm.etsi.org:29418/osm/$i
    fi
    git -C $i checkout master
    git -C $i pull --rebase
    git -C $i tag -a "release-$BRANCH-start" -m"$tag_message"
    git -C $i push origin $TAG --follow-tags
    git -C $i checkout -b "$BRANCH"
    git -C $i push -u origin "$BRANCH"
done

exit 0
