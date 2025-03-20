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

export OS_CLOUD=nameofmyopenstack
export VIM_MGMT_NET="internal"  # Internal network to attach the VM
export VIM_EXT_NET="ext-net"    # External network providing floating IP addresses

# Converts the name of the internal network to UUID, so that Packer can use it
export NETWORK_ID=`openstack network list -f json | jq -r ".[] | select(.Name == \"${VIM_MGMT_NET}\") | .ID"`

# Other environment variables for Packer
export FLAVOR_NAME=flavorname
export SOURCE_IMAGE_NAME=sourceimagename
