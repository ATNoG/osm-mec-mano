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


# Helper function to monitor progress of a condition
function monitor_condition() {
    local CONDITION="$1"        # Function with the condition
    local MESSAGE="${2:-}"      # Message during each check
    local TIMEOUT="${3:-300}"   # Timeout, in seconds (default: 5 minutes)
    local STEP="${4:-2}"        # Polling period (default: 2 seconds)

    "${CONDITION}"
    RET=$?
    until [ ${RET} -eq 0 ] || [ ${TIMEOUT} -le 0 ]
    do
        echo -en "${MESSAGE}"

        ((TIMEOUT-=${STEP}))
        sleep "${STEP}"

        "${CONDITION}"
        RET=$?
    done

    return ${RET}
}
