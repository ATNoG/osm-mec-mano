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

FROM ubuntu:22.04 as FINAL

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

#######################################################################################
# End of common preparation

RUN DEBIAN_FRONTEND=noninteractive apt-get --yes update && \
    DEBIAN_FRONTEND=noninteractive apt-get --yes install \
    apt-transport-https \
    ca-certificates \
    gettext-base=0.21* \
    git=1:2.34.* \
    gnupg \
    iputils-ping=3:* \
    jq=1.6* \
    libmagic1=1:5.*

ARG OSM_TESTS_URL
ARG PYTHON3_OSM_IM_URL
ARG PYTHON3_OSMCLIENT_URL

RUN curl $PYTHON3_OSM_IM_URL -o osm_im.deb
RUN dpkg -i ./osm_im.deb

RUN curl $PYTHON3_OSMCLIENT_URL -o osmclient.deb
RUN dpkg -i ./osmclient.deb

RUN curl $OSM_TESTS_URL -o osm_tests.deb
RUN dpkg -i ./osm_tests.deb

RUN pip3 install \
    -r /usr/lib/python3/dist-packages/osm_im/requirements.txt \
    -r /usr/lib/python3/dist-packages/osmclient/requirements.txt \
    -r /usr/share/osm-tests/requirements.txt

# kubectl
# https://kubernetes.io/releases/
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
    && echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list \
    && apt-get update && apt-get install -y kubectl=1.30.1-1.1

# Google Cloud CLI
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
RUN curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
RUN DEBIAN_FRONTEND=noninteractive apt-get --yes update && \
    DEBIAN_FRONTEND=noninteractive apt-get --yes install \
    google-cloud-cli=455.*

# Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Add vCluster CLI
ENV VCLUSTER_VERSION "v0.26.0"
RUN curl -L -o /tmp/vcluster "https://github.com/loft-sh/vcluster/releases/download/${VCLUSTER_VERSION}/vcluster-linux-amd64" \
    && install -c -m 0755 /tmp/vcluster /usr/local/bin \
    && rm -f /tmp/vcluster
# Copy vCluster configuration
COPY configs/vcluster.yaml /etc/vcluster.yaml

RUN mv /usr/share/osm-tests/robot-systest /robot-systest
RUN mv /usr/share/osm-tests/cloud-scripts /robot-systest/
RUN mv /usr/share/osm-tests/conformance-tests/ /robot-systest/
RUN mv /usr/share/osm-tests/charm.sh /usr/sbin/charm

ARG CACHE_DATE=not_a_date
RUN git clone \
    https://osm.etsi.org/gitlab/vnf-onboarding/osm-packages.git \
    --recurse-submodules \
    /robot-systest/osm-packages

WORKDIR /robot-systest

# Folder where Robot tests are stored
ENV ROBOT_DEVOPS_FOLDER=/robot-systest

# Folder to save alternative DUT environments (optional)
ENV ENVIRONMENTS_FOLDER=environments

# Folder where all required packages are stored
ENV PACKAGES_FOLDER=/robot-systest/osm-packages

# Folder where test results should be exported
ENV ROBOT_REPORT_FOLDER=/robot-systest/results

# Kubeconfig file
ENV K8S_CREDENTIALS=/root/.kube/config

# Kubeconfig file of the existing cluster for Gitops tests
ENV CLUSTER_KUBECONFIG_CREDENTIALS=/robot-systest/cluster-kubeconfig.yaml

# OSM RSA file
ENV OSM_RSA_FILE=/root/osm_id_rsa

ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

ENTRYPOINT [ "/robot-systest/run_test.sh"]
