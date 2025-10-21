#######################################################################################
# Copyright ETSI Contributors and Others.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#######################################################################################

FROM alpine:3.21.3 
# FROM ghcr.io/nushell/nushell:0.104.0-alpine

ARG NUSHELL_VERSION=0.104.1


# Install Nushell for Alpine
#-----------------------------------------------------
#
RUN echo '/usr/bin/nu' >> /etc/shells \
    && adduser -D -s /usr/bin/nu nushell \
    && mkdir -p /home/nushell/.config/nushell/ \
    && cd /tmp \
    && wget "https://github.com/nushell/nushell/releases/download/${NUSHELL_VERSION}/nu-${NUSHELL_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    && mkdir nu-${NUSHELL_VERSION} && tar xvf nu-*.tar.gz --directory=nu-${NUSHELL_VERSION} \
    && cp -aR nu-${NUSHELL_VERSION}/**/* /usr/bin/ \
    # Setup default config file for nushell
    && cd /home/nushell/.config/nushell \
    && chmod +x /usr/bin/nu \
    && chown -R nushell:nushell /home/nushell/.config/nushell \
    # Reset Nushell config to default
    && su -c 'config reset -w' nushell \
    && ls /usr/bin/nu_plugin* \
    | xargs -I{} su -c 'plugin add {}' nushell \
    && rm -rf /tmp/*
#
#-----------------------------------------------------

# Install dependencies
RUN apk add --no-cache \
        age \
        envsubst \
        git \
        kubectl \
        sops && \
    # Install dependencies unavailable at Alpine repos
    wget https://github.com/kptdev/kpt/releases/download/v1.0.0-beta.57/kpt_linux_amd64 -O kpt && \
        chmod +x kpt && \
        mv kpt /usr/local/bin/ && \
    # Create default folders and files
    mkdir -p /repos && \
        chmod 755 /repos && \
    mkdir -p /model/parameters/clear && \
    mkdir -p /model/parameters/secret && \
        chmod -R 755 /model && \
        echo '{}' > /model/app_instance_model.yaml && \
        echo '{}' > /model/parameters/clear/environment.yaml && \
        echo '{}' > /model/parameters/secret/environment.yaml


# Become the standard user
USER nushell
WORKDIR /app

# Add libraries and helper scripts
COPY --chown=nushell:nushell scripts /app/scripts
COPY --chown=nushell:nushell krm /app/osm/krm
COPY --chown=nushell:nushell operations /app/osm/operations

# Add the entrypoint and default command
ENTRYPOINT ["/bin/sh", "/app/scripts/entrypoint.sh"]

CMD ["nu"]
