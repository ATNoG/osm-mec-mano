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

my_custom_motd='
This system was built by Telefónica I+D for ETSI Open Source MANO (ETSI OSM)'

if [ -d /etc/update-motd.d ]; then
    MOTD_CONFIG='/etc/update-motd.d/99-custom'

    cat >> "$MOTD_CONFIG" <<FINAL
#!/bin/sh

cat <<'EOF'
$my_custom_motd
EOF
FINAL

    chmod 0755 "$MOTD_CONFIG"
else
    echo "$my_custom_motd" >> /etc/motd
fi
