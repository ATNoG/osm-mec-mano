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

set +eux

function configure_containerd() {
    echo "Configuring containerd to expose CRI and use systemd cgroup"
    sudo mv /etc/containerd/config.toml /etc/containerd/config.toml.orig 2>/dev/null
    sudo bash -c "containerd config default > /etc/containerd/config.toml"
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    if [ -n "${DOCKER_PROXY_URL}" ]; then
        echo "Configuring ${DOCKER_PROXY_URL} as registry mirror in /etc/containerd/config.toml"
        sudo sed -i "s#\[plugins.\"io.containerd.grpc.v1.cri\".registry.mirrors\]#\[plugins.\"io.containerd.grpc.v1.cri\".registry.mirrors\]\n        \[plugins.\"io.containerd.grpc.v1.cri\".registry.mirrors.\"docker.io\"\]\n          endpoint = \[\"${DOCKER_PROXY_URL}\"\]\n        \[plugins.\"io.containerd.grpc.v1.cri\".registry.mirrors.\"registry.hub.docker.com\"]\n          endpoint = \[\"${DOCKER_PROXY_URL}\"]#" /etc/containerd/config.toml
    fi
    if [ -n "${OSM_BEHIND_PROXY}" ] ; then
        echo "Configuring http proxies in /etc/systemd/system/containerd.service.d/http-proxy.conf"
        if ! [ -f /etc/systemd/system/containerd.service.d/http-proxy.conf ] ; then
            sudo mkdir -p /etc/systemd/system/containerd.service.d
            cat << EOF | sudo tee -a /etc/systemd/system/containerd.service.d/http-proxy.conf
[Service]
EOF
        fi
        [ -n "${HTTP_PROXY}" ] && sudo bash -c "cat <<EOF >> /etc/systemd/system/containerd.service.d/http-proxy.conf
Environment=\"HTTP_PROXY=${HTTP_PROXY}\"
EOF"
        [ -n "${HTTPS_PROXY}" ] && sudo bash -c "cat <<EOF >> /etc/systemd/system/containerd.service.d/http-proxy.conf
Environment=\"HTTPS_PROXY=${HTTPS_PROXY}\"
EOF"
        [ -n "${NO_PROXY}" ] && sudo bash -c "cat <<EOF >> /etc/systemd/system/containerd.service.d/http-proxy.conf
Environment=\"NO_PROXY=${NO_PROXY}\"
EOF"
    fi
    sudo systemctl restart containerd
}

function install_docker_ce() {
    # installs and configures Docker CE
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    echo "Removing previous installation of docker ..."
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove $pkg; done
    echo "Installing Docker CE ..."
    sudo apt-get -y update
    sudo apt-get install -y apt-transport-https ca-certificates software-properties-common gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get -y update
    sudo apt-get install -y docker-ce

    echo "Adding user to group 'docker'"
    sudo groupadd -f docker
    sudo usermod -aG docker $USER

    if [ -n "${DOCKER_PROXY_URL}" ]; then
        echo "Configuring docker proxy ..."
        if [ -f /etc/docker/daemon.json ]; then
            if grep -q registry-mirrors /etc/docker/daemon.json; then
                sudo sed -i "s|registry-mirrors.*|registry-mirrors\": [\"${DOCKER_PROXY_URL}\"] |" /etc/docker/daemon.json
            else
                sudo sed -i "s|^{|{\n  \"registry-mirrors\": [\"${DOCKER_PROXY_URL}\"],|" /etc/docker/daemon.json
            fi
        else
            sudo bash -c "cat << EOF > /etc/docker/daemon.json
{
  \"registry-mirrors\": [\"${DOCKER_PROXY_URL}\"]
}
EOF"
        fi
    fi
    if [ -n "${OSM_BEHIND_PROXY}" ] ; then
        if ! [ -f /etc/systemd/system/docker.service.d/http-proxy.conf ] ; then
            sudo mkdir -p /etc/systemd/system/docker.service.d
            cat << EOF | sudo tee -a /etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
EOF
        fi
        [ -n "${HTTP_PROXY}" ] && sudo bash -c "cat <<EOF >> /etc/systemd/system/docker.service.d/http-proxy.conf
Environment=\"HTTP_PROXY=${HTTP_PROXY}\"
EOF"
        [ -n "${HTTPS_PROXY}" ] && sudo bash -c "cat <<EOF >> /etc/systemd/system/docker.service.d/http-proxy.conf
Environment=\"HTTPS_PROXY=${HTTPS_PROXY}\"
EOF"
        [ -n "${NO_PROXY}" ] && sudo bash -c "cat <<EOF >> /etc/systemd/system/docker.service.d/http-proxy.conf
Environment=\"NO_PROXY=${NO_PROXY}\"
EOF"
    fi
    if [ -n "${DOCKER_PROXY_URL}" ] || [ -n "${OSM_BEHIND_PROXY}" ] ; then
        sudo systemctl daemon-reload
        sudo systemctl restart docker
        echo "... restarted Docker service"
    fi

    configure_containerd

    [ -z "${DEBUG_INSTALL}" ] || ! echo "File: /etc/docker/daemon.json" || cat /etc/docker/daemon.json
    echo "Testing Docker CE installation ..."
    sg docker -c "docker version" || FATAL_TRACK docker_ce "Docker installation failed. Cannot run docker version"
    sg docker -c "docker run --rm hello-world" || FATAL_TRACK docker_ce "Docker installation failed. Cannot run hello-world"
    echo "... Docker CE installation done"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
    return 0
}

DEBUG_INSTALL=${DEBUG_INSTALL:-}
OSM_DEVOPS=${OSM_DEVOPS:-"/usr/share/osm-devops"}
DOCKER_PROXY_URL=${DOCKER_PROXY_URL:-}
OSM_BEHIND_PROXY=${OSM_BEHIND_PROXY:-}
echo "DEBUG_INSTALL=$DEBUG_INSTALL"
echo "OSM_DEVOPS=$OSM_DEVOPS"
echo "DOCKER_PROXY_URL=$DOCKER_PROXY_URL"
echo "OSM_BEHIND_PROXY=$OSM_BEHIND_PROXY"
echo "USER=$USER"

source $OSM_DEVOPS/library/logging

install_docker_ce
