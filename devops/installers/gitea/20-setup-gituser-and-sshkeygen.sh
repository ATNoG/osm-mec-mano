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

set -e -o pipefail

# Test if the user exists. Otherwise, create a git user
echo "Test if there is a git user. Otherwise, create it."
if [ ! -n "$(git config user.name)" ]; then
    git config --global user.name osm_user
    git config --global user.email osm_user@mydomain.com
fi

# Test if the user exists. Otherwise, create a git user
echo "Checking if the user has an SSH key pair"
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    echo "Generating an SSH key pair for the user"
    ssh-keygen -t rsa -f "$HOME/.ssh/id_rsa" -N "" -q
fi
