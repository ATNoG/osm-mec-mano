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


RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Colored messages (blue is the default)
# Examples:
#   m "hello world"
#   m "hello world" "$GREEN"
function m() {
  local COLOR=${2:-$BLUE}
  echo -e "$COLOR$1$RESET"
}

function copy_function() {
  local ORIG_FUNC=$(declare -f $1)
  local NEWNAME_FUNC="$2${ORIG_FUNC#$1}"
  eval "$NEWNAME_FUNC"
}

function replace_text() {
  local FILE=$1
  local START=$2
  local END=$3
  local NEW=$4
  local T=$(mktemp)
  head -n $((START-1)) "$FILE" > "$T"
  echo "$NEW" >> "$T"
  tail -n +$((END+1)) "$FILE" >> "$T"
  mv "$T" "$FILE"
}

function insert_text() {
  local FILE=$1
  local START=$2
  local NEW=$3
  local T=$(mktemp)
  head -n $((START-1)) "$FILE" > "$T"
  echo "$NEW" >> "$T"
  tail -n +$START "$FILE" >> "$T"
  mv "$T" "$FILE"
}

function remove_text() {
  local FILE=$1
  local START=$2
  local END=$3
  local T=$(mktemp)
  head -n $((START-1)) "$FILE" > "$T"
  tail -n +$((END+1)) "$FILE" >> "$T"
  mv "$T" "$FILE"
}

function envsubst_cp() {
  local FROM_FILE=$1
  local TO_FILE=$2
  mkdir --parents "$(dirname "$TO_FILE")"
  cat "$FROM_FILE" | envsubst > "$TO_FILE"
}

function envsubst_dir() {
  local FROM_DIR=$1
  local TO_DIR=$2
  rm --recursive --force "$TO_DIR"
  mkdir --parents "$TO_DIR"
  pushd "$FROM_DIR" > /dev/null
  local F
  find . -type f | while read F; do
    envsubst_cp "$F" "$TO_DIR/$F"
  done
  popd > /dev/null
}
