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

source ../library/track
source ../library/logging

RELEASE="test_track"
OSM_DOCKER_TAG=latest
OSM_TRACK_INSTALLATION_ID="$(date +%s)-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)"

echo "Next track call should fail"
echo "track"
track
echo
echo "Next, several track calls are done with different args" 
echo "track test-event"
track test-event
sleep 1
echo "track test-event release $RELEASE"
track test-event release $RELEASE
sleep 1
echo "track test-event docker_tag $OSM_DOCKER_TAG none none"
track test-event docker_tag $OSM_DOCKER_TAG none none
sleep 1
echo "track test-event release $RELEASE none none docker_tag $OSM_DOCKER_TAG none none"
track test-event release $RELEASE none none docker_tag $OSM_DOCKER_TAG none none
sleep 1
echo 'track test-event my-op my-value "My comment" none'
track test-event my-op my-value "My comment" none
sleep 1
echo 'track test-event my-op my-value "My comment" "tag1,tag2"'
track test-event my-op my-value "My comment" "tag1,tag2"
sleep 1
echo 'track test-event op1 value1 "My comment1 on test event" none op2 value2 "My comment2 on test event" none'
track test-event op1 value1 "My comment1 on test event" none op2 value2 "My comment2 on test event" none
sleep 1
echo
echo "Next track call will be done from function FATAL_TRACK"
echo 'FATAL_TRACK test-fatal "Fatal error during execution"'
FATAL_TRACK test-fatal "Fatal error during execution"

