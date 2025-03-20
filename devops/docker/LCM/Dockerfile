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

FROM ubuntu:22.04 as INSTALL

ARG APT_PROXY
RUN if [ ! -z $APT_PROXY ] ; then \
    echo "Acquire::http::Proxy \"$APT_PROXY\";" > /etc/apt/apt.conf.d/proxy.conf ;\
    echo "Acquire::https::Proxy \"$APT_PROXY\";" >> /etc/apt/apt.conf.d/proxy.conf ;\
    fi

RUN DEBIAN_FRONTEND=noninteractive apt-get --yes update && \
    DEBIAN_FRONTEND=noninteractive apt-get --yes install \
    gcc=4:11.* \
    python3=3.10.* \
    python3-dev=3.10.* \
    python3-pip=22.0.* \
    curl=7.81.* \
    && rm -rf /var/lib/apt/lists/*

########### End of common preparation

RUN DEBIAN_FRONTEND=noninteractive apt-get --yes update && \
    DEBIAN_FRONTEND=noninteractive apt-get --yes install \
    apt-transport-https=2.4.* \
    gnupg2=2.2.* \
    openssh-client=1:8.* \
    && rm -rf /var/lib/apt/lists/*

# https://kubernetes.io/releases/
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
    && echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list \
    && apt-get update && apt-get install -y kubectl=1.30.1-1.1

# https://github.com/helm/helm/releases
RUN curl https://get.helm.sh/helm-v3.15.1-linux-amd64.tar.gz --output helm-v3.15.1.tar.gz \
    && tar -zxvf helm-v3.15.1.tar.gz \
    && mv linux-amd64/helm /usr/local/bin/helm3 \
    && rm -r linux-amd64/

ARG PYTHON3_OSM_COMMON_URL
ARG PYTHON3_OSM_LCM_URL

RUN curl $PYTHON3_OSM_COMMON_URL -o osm_common.deb
RUN dpkg -i ./osm_common.deb

RUN curl $PYTHON3_OSM_LCM_URL -o osm_lcm.deb
RUN dpkg -i ./osm_lcm.deb

RUN pip3 install \
    -r /usr/lib/python3/dist-packages/osm_common/requirements.txt \
    -r /usr/lib/python3/dist-packages/osm_lcm/requirements.txt

#######################################################################################
FROM ubuntu:22.04 as FINAL

ARG APT_PROXY
RUN if [ ! -z $APT_PROXY ] ; then \
    echo "Acquire::http::Proxy \"$APT_PROXY\";" > /etc/apt/apt.conf.d/proxy.conf ;\
    echo "Acquire::https::Proxy \"$APT_PROXY\";" >> /etc/apt/apt.conf.d/proxy.conf ;\
    fi

RUN DEBIAN_FRONTEND=noninteractive apt-get --yes update && \
    DEBIAN_FRONTEND=noninteractive apt-get --yes install \
    python3-minimal=3.10.* \
    && rm -rf /var/lib/apt/lists/*

COPY --from=INSTALL /usr/lib/python3/dist-packages /usr/lib/python3/dist-packages
COPY --from=INSTALL /usr/local/lib/python3.10/dist-packages  /usr/local/lib/python3.10/dist-packages

#######################################################################################
# End of common preparation

RUN DEBIAN_FRONTEND=noninteractive apt-get --yes update && \
    DEBIAN_FRONTEND=noninteractive apt-get --yes install \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN rm -f /etc/apt/apt.conf.d/proxy.conf

COPY --from=INSTALL /usr/bin/kubectl /usr/bin/kubectl
COPY --from=INSTALL /usr/local/bin/helm3 /usr/local/bin/helm3
COPY --from=INSTALL /usr/bin/scp /usr/bin/scp
COPY --from=INSTALL /usr/bin/ssh-keygen /usr/bin/ssh-keygen
COPY --from=INSTALL /usr/bin/ssh /usr/bin/ssh
COPY --from=INSTALL /usr/lib/x86_64-linux-gnu/ /usr/lib/x86_64-linux-gnu/
COPY --from=INSTALL /lib/x86_64-linux-gnu/ /lib/x86_64-linux-gnu/

COPY scripts/ /app/osm_lcm/scripts/

# Creating the user for the app
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g 1000 -d /app appuser && \
    mkdir -p /app/osm_lcm && \
    mkdir -p /app/storage/kafka && \
    mkdir /app/log && \
    chown -R appuser:appuser /app && \
    chown appuser: /etc/ssl/certs/ca-certificates.crt


WORKDIR /app/osm_lcm

# Changing the security context
USER appuser

########################################################################

# The following ENV can be added with "docker run -e xxx' to configure LCM
ENV OSMLCM_RO_HOST         ro
ENV OSMLCM_RO_PORT         9090
ENV OSMLCM_RO_TENANT       osm

# VCA
ENV OSMLCM_VCA_HOST        vca
ENV OSMLCM_VCA_PORT       17070
ENV OSMLCM_VCA_USER       admin
ENV OSMLCM_VCA_SECRET     secret
# ENV OSMLCM_VCA_PUBKEY     pubkey
# ENV OSMLCM_VCA_CACERT     cacert
# ENV OSMLCM_VCA_ENABLEOSUPGRADE false
# ENV OSMLCM_VCA_APTMIRROR  http://archive.ubuntu.com/ubuntu/

# database
ENV OSMLCM_DATABASE_DRIVER mongo
ENV OSMLCM_DATABASE_URI    mongodb://mongo:27017
#ENV OSMLCM_DATABASE_HOST    mongo
#ENV OSMLCM_DATABASE_PORT    27017


ENV OSMLCM_STORAGE_DRIVER  local
ENV OSMLCM_STORAGE_PATH    /app/storage

# message
ENV OSMLCM_MESSAGE_DRIVER  kafka
ENV OSMLCM_MESSAGE_HOST    kafka
ENV OSMLCM_MESSAGE_PORT    9092

# k8s
ENV OSMLCM_VCA_HELMPATH    /usr/local/bin/helm3
ENV OSMLCM_VCA_KUBECTLPATH /usr/bin/kubectl
ENV OSMLCM_VCA_JUJUPATH    /usr/local/bin/juju

# post-renderers
ENV OSMLCM_MAINPOSTRENDERERPATH    /app/osm_lcm/n2vc/post-renderer-scripts/mainPostRenderer/mainPostRenderer
ENV OSMLCM_PODLABELSPOSTRENDERERPATH    /app/osm_lcm/n2vc/post-renderer-scripts/podLabels/podLabels
ENV OSMLCM_NODESELECTORPOSTRENDERERPATH    /app/osm_lcm/n2vc/post-renderer-scripts/nodeSelector/nodeSelector

# helm
ENV OSMLCM_VCA_STABLEREPOURL https://charts.helm.sh/stable
# ENV OSMLCM_VCA_HELM_CA_CERTS <ca-cert>

# logs
# ENV OSMLCM_GLOBAL_LOGFILE  /app/log/lcm.log
# ENV OSMLCM_GLOBAL_LOGLEVEL DEBUG

HEALTHCHECK --start-period=120s --interval=30s --timeout=30s --retries=1 \
  CMD python3 -m osm_lcm.lcm_hc || exit 1

# Run app.py when the container launches
CMD [ "/bin/bash", "scripts/start.sh" ]
