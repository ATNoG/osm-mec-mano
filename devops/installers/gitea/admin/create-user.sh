#!/bin/bash
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

set -e

HERE=$(dirname "$(readlink --canonicalize "$BASH_SOURCE")")
source "${HERE}/../library/functions.sh"
source "${HERE}/../library/trap.sh"

USERNAME=$1
PASSWORD="${2}"
EMAIL=$3

"$HERE/gitea.sh" admin user create \
	--username "$USERNAME" \
	--password \'"${PASSWORD}"\' \
	--email "$EMAIL" \
	--must-change-password=false \
	"${@:4}"
