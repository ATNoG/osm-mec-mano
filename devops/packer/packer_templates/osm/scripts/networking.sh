#!/bin/sh -eux

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

ubuntu_version="`lsb_release -r | awk '{print $2}'`";
major_version="`echo $ubuntu_version | awk -F. '{print $1}'`";

if [ "$major_version" -ge "18" ]; then
echo "Create netplan config for eth0"
cat <<EOF >/etc/netplan/01-netcfg.yaml;
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
EOF
else
  # Adding a 2 sec delay to the interface up, to make the dhclient happy
  echo "pre-up sleep 2" >> /etc/network/interfaces;
fi

if [ "$major_version" -ge "16" ]; then
  # Disable Predictable Network Interface names and use eth0
  sed -i 's/en[[:alnum:]]*/eth0/g' /etc/network/interfaces;
  sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0 \1"/g' /etc/default/grub;
  update-grub;
fi
