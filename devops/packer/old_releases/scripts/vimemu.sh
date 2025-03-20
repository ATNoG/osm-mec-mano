#!/bin/sh

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

mkdir -p /etc/systemd/system/scripts
cat > /etc/systemd/system/scripts/osm-vimemu-startup.sh <<-'EOF'
#!/bin/sh

export OSM_HOSTNAME=127.0.0.1
export OSM_SOL005=True

echo "Waiting for OSM startup"
while true; do
    # wait for startup of osm
    RC=$(osm vim-list)
    if [ "$?" -eq 0 ]; then
        break
    fi
    sleep 2
done
echo "OSM is up"
sleep 10
export VIMEMU_HOSTNAME=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vim-emu)
osm vim-create --name vim-emulator --user username --password password --auth_url http://$VIMEMU_HOSTNAME:6001/v2.0 --tenant tenantName --account_type openstack
osm vnfd-create /home/vagrant/vim-emu/examples/vnfs/ping.tar.gz
osm vnfd-create /home/vagrant/vim-emu/examples/vnfs/pong.tar.gz
osm nsd-create /home/vagrant/vim-emu/examples/services/pingpong_nsd.tar.gz
osm ns-create --nsd_name pingpong --ns_name test --vim_account vim-emulator

echo "VIM emulator created"
systemctl disable osm-vimemu-setup.service
EOF
chmod +x /etc/systemd/system/scripts/osm-vimemu-startup.sh

cat > /etc/systemd/system/osm-vimemu-setup.service <<-'EOF'
[Unit]
Description=OSM VIM emulator setup

[Service]
Type=oneshot
ExecStart=/etc/systemd/system/scripts/osm-vimemu-startup.sh
RemainAfterExit=yes
TimeoutSec=120

# Output needs to appear in instance console output
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

#systemctl enable osm-vimemu-setup.service
