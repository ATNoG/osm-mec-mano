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

function goodbye() {
  local DURATION=$(date --date=@$(( "$(date +%s)" - "$TRAP_START_TIME" )) --utc +%T)
  local CODE=$1
  cd "$TRAP_DIR"
  if [ "$CODE" == 0 ]; then
    m "$(realpath --relative-to="$HERE" "$0") succeeded! $DURATION" "$GREEN"
  elif [ "$CODE" == abort ]; then
    m "Aborted $(realpath --relative-to="$HERE" "$0")! $DURATION" "$RED"
  else
    m "Oh no! $(realpath --relative-to="$HERE" "$0") failed! $DURATION" "$RED"
  fi
}

function trap_EXIT() {
  local ERR=$?
  goodbye "$ERR"
  exit "$ERR"
}

function trap_INT() {
  goodbye abort
  trap - EXIT
  exit 1
}

TRAP_DIR=$PWD
TRAP_START_TIME=$(date +%s)

trap trap_INT INT

trap trap_EXIT EXIT
