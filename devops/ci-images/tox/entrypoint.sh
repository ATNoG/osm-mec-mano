#!/usr/bin/env bash
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

set -euo pipefail

UID=${UID:-10000}
GID=${GID:-10000}

# ensure group exists with given GID
if ! getent group "${GID}" > /dev/null; then
  groupmod -o -g "${GID}" tox 2>/dev/null \
    || groupadd -o -g "${GID}" tox
fi

# ensure tox user has the given UID
usermod -o -u "${UID}" -g "${GID}" tox \
  || useradd -o -m -u "${UID}" -g "${GID}" tox

exec su tox "$@"
