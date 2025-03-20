#!/bin/bash

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

export PATH=$PATH:/snap/bin
echo "PATH=$PATH"
juju status

wget https://osm-download.etsi.org/ftp/osm-5.0-five/install_osm.sh
chmod +x install_osm.sh
./install_osm.sh --nolxd --nojuju -y

cat >> ~/.bashrc <<-EOF
export OSM_HOSTNAME=127.0.0.1
export OSM_SOL005=True

EOF
