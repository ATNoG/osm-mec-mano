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

sudo lxd init --auto --storage-backend zfs --storage-pool lxdpool --storage-create-loop 20

sudo systemctl stop lxd-bridge
sudo systemctl --system daemon-reload

sudo cp -f /tmp/lxd-bridge /etc/default/lxd-bridge
sudo systemctl enable lxd-bridge
sudo systemctl start lxd-bridge

sudo usermod -a -G lxd $(whoami) 
