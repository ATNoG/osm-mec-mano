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

function usage(){
    echo -e "usage: $0 (OPTIONS)"
    echo -e "Replaces original host IP address (typically saved at /home/vagrant/oldIPaddress.txt) where VCA listens in OSM configuration by a new one. Also used by docker swarm."
    echo -e "  OPTIONS"
    echo -e "     -n <new_ip_addr>:   new host ip address (default: current IP address)"
    echo -e "     -o <old_ip_addr>:   old host ip address during initial install (default: content of /etc/osm/oldIPaddress.txt)"
    echo -e "     -h / --help:        print this help"
}

while getopts ":n:o:-:h" o; do
    case "${o}" in
        n)
            CURRENT_IP_ADDRESS="${OPTARG}"
            ;;
        o)
            OLD_IP_ADDRESS="${OPTARG}"
            ;;
        -)
            [ "${OPTARG}" == "help" ] && usage && exit 0
            ;;
        :)
            echo "Option -$OPTARG ip address required" >&2
            usage && exit 1
            ;;
        \?)
            echo -e "Invalid option: '-$OPTARG'\n" >&2
            usage && exit 1
            ;;
        h)
            usage && exit 0
            ;;
        *)
            usage && exit 1
            ;;
    esac
done

if [ -z "$CURRENT_IP_ADDRESS" ]
then
    DEFAULT_IF=$(route -n |awk '$1~/^0.0.0.0/ {print $8}')
    CURRENT_IP_ADDRESS=$(ip -o -4 a |grep ${DEFAULT_IF}|awk '{split($4,a,"/"); print a[1]}')
fi
[ -z "$OLD_IP_ADDRESS" ] && OLD_IP_ADDRESS=$(cat /etc/osm/oldIPaddress.txt)

VCA_HOST=$(cat /etc/osm/docker/lcm.env | grep OSMLCM_VCA_HOST | cut -f2 -d=)

sudo sed -i "s/$OLD_IP_ADDRESS/$CURRENT_IP_ADDRESS/g" /etc/osm/docker/lcm.env
sudo sed -i "s/$OLD_IP_ADDRESS/$CURRENT_IP_ADDRESS/g" /etc/osm/docker/mon.env
docker stack rm osm
sleep 20

# Clean previous ip address info from Docker Swarm and reinitialize
docker swarm leave --force
docker swarm init --advertise-addr $CURRENT_IP_ADDRESS
sudo systemctl restart docker
docker network create --driver=overlay --attachable --opt com.docker.network.driver.mtu=1500 netosm

# Deploy docker stack
source /etc/osm/docker/osm_ports.sh
docker stack deploy -c /etc/osm/docker/docker-compose.yaml osm

sudo iptables -t nat -D PREROUTING -p tcp -m tcp -d $OLD_IP_ADDRESS --dport 17070 -j DNAT --to-destination $VCA_HOST
sudo iptables -t nat -A PREROUTING -p tcp -m tcp -d $CURRENT_IP_ADDRESS --dport 17070 -j DNAT --to-destination $VCA_HOST

echo "[DONE]"
