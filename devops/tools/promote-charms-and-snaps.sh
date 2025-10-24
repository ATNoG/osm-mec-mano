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

CHANNEL=${1:-latest}
SOURCE=${2:-beta}
TARGET=${3:-candidate}
echo "==========================================================="
echo Promoting charms and snaps from $SOURCE to $TARGET
echo ""

for snap in osmclient ; do

    echo "==========================================================="
    echo "${snap}"

    track="${CHANNEL}/${SOURCE}\\*"
    SOURCE_REV=$(snapcraft revisions $snap | grep $track | tail -1 | awk '{print $1}')
    track="${CHANNEL}/${TARGET}\\*"
    TARGET_REV=$(snapcraft revisions $snap | grep $track | tail -1 | awk '{print $1}')

    echo "$SOURCE: $SOURCE_REV, $TARGET: $TARGET_REV"

    if [ -z $TARGET_REV ] || [ $SOURCE_REV -ne $TARGET_REV ]; then
        echo "Promoting $SOURCE_REV to beta in place of $TARGET_REV"
        track="${CHANNEL}/${TARGET}"
        snapcraft release $snap $SOURCE_REV $track
    fi

done

for charm in \
    'osm' \
    'osm-ha' \
    'osm-grafana' \
    'mongodb-exporter-k8s' \
    'mysqld-exporter-k8s' \
    'osm-lcm' \
    'osm-mon' \
    'osm-nbi' \
    'osm-ng-ui' \
    'osm-pol' \
    'osm-ro' \
    'osm-prometheus' \
    'osm-vca-integrator' ; do

    echo "==========================================================="
    echo "${charm}"

    charmcraft status $charm --format json > ${charm}.json
    isCharm=$(grep architecture ${charm}.json | wc -l 2>/dev/null)
    resourceArgument=""

    if [ $isCharm -gt 0 ]; then
        base=20.04
        is2204=$(cat ${charm}.json | jq -r ".[] | select(.track==\"$CHANNEL\") | .mappings[] | select(.base.architecture==\"amd64\" and .base.channel==\"22.04\")"|wc -l)
        if [ $is2204 -gt 0 ]; then
            base=22.04
        fi


        SOURCE_REV=$(cat ${charm}.json | jq -r ".[] | select(.track==\"$CHANNEL\") | .mappings[] | select(.base.architecture==\"amd64\" and .base.channel==\"$base\") | .releases[] | select(.channel==\"$CHANNEL/$SOURCE\")| .version"|head -1)
        TARGET_REV=$(cat ${charm}.json | jq -r ".[] | select(.track==\"$CHANNEL\") | .mappings[] | select(.base.architecture==\"amd64\" and .base.channel==\"$base\") | .releases[] | select(.channel==\"$CHANNEL/$TARGET\")| .version"|head -1)


        index=0
        while [ $index -lt 5 ]; do
            resourceName=$(cat ${charm}.json | jq -r ".[] | select(.track==\"$CHANNEL\") | .mappings[] | select(.base.architecture==\"amd64\" and .base.channel==\"$base\") | .releases[] | select(.channel==\"$CHANNEL/$SOURCE\")| .resources[$index].name"|head -1)
            resourceRevs=$(cat ${charm}.json | jq -r ".[] | select(.track==\"$CHANNEL\") | .mappings[] | select(.base.architecture==\"amd64\" and .base.channel==\"$base\") | .releases[] | select(.channel==\"$CHANNEL/$SOURCE\")| .resources[$index].revision"|head -1)
            if [ "$resourceName" != "null" ] ; then
                resourceArgument=" $resourceArgument --resource ${resourceName}:${resourceRevs}"
            else
                break
            fi
            ((index=index+1))
        done
    else
        SOURCE_REV=$(cat ${charm}.json | jq -r ".[] | select(.track==\"$CHANNEL\") | .mappings[].releases[] | select(.channel==\"$CHANNEL/$SOURCE\")| .version"|head -1)
        TARGET_REV=$(cat ${charm}.json | jq -r ".[] | select(.track==\"$CHANNEL\") | .mappings[].releases[] | select(.channel==\"$CHANNEL/$TARGET\")| .version"|head -1)
    fi

    rm ${charm}.json
    echo "$SOURCE: $SOURCE_REV, $TARGET: $TARGET_REV $resourceArgument"

    if [ $TARGET_REV == "null" ] || [ $SOURCE_REV -gt $TARGET_REV ] ; then
        echo Promoting ${charm} revision ${SOURCE_REV} to ${TARGET} ${resourceArgument}
        charmcraft release ${charm} --revision=${SOURCE_REV}  ${resourceArgument} --channel=${CHANNEL}/$TARGET
    fi

done
