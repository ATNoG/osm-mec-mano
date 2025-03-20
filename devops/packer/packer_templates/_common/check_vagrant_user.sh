#!/bin/bash -eux

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

# This script is intended for VIMs-type builders such as OpenStack, which
# use cloud images where the `vagrant` user does not exist by default

USER=vagrant
USER_NAME=vagrant
PASSWORD=vagrant

# If the `vagrant` user does not exist, it is created
(id ${USER} >/dev/null 2>&1) || adduser --disabled-password --gecos "${USER_NAME}" "${USER}"

# Comment if no password should be set
echo "${USER}:${PASSWORD}" | sudo chpasswd
