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

#######################################################################################
# End of common preparation

RUN DEBIAN_FRONTEND=noninteractive apt-get --yes update && \
    DEBIAN_FRONTEND=noninteractive apt-get --yes install \
    openssh-client=1:8.*

ARG PYTHON3_OSM_COMMON_URL
ARG PYTHON3_OSM_MON_URL

RUN curl $PYTHON3_OSM_COMMON_URL -o osm_common.deb
RUN dpkg -i ./osm_common.deb

RUN curl $PYTHON3_OSM_MON_URL -o osm_mon.deb
RUN dpkg -i ./osm_mon.deb

RUN pip3 install \
    -r /usr/lib/python3/dist-packages/osm_common/requirements.txt \
    -r /usr/lib/python3/dist-packages/osm_mon/requirements.txt

#######################################################################################
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

COPY --from=INSTALL /usr/bin/osm* /usr/bin/
COPY --from=INSTALL /usr/bin/scp /usr/bin/scp
COPY --from=INSTALL /usr/bin/ssh-keygen /usr/bin/ssh-keygen
COPY --from=INSTALL /usr/bin/ssh /usr/bin/ssh
COPY --from=INSTALL /usr/lib/x86_64-linux-gnu/ /usr/lib/x86_64-linux-gnu/
COPY --from=INSTALL /lib/x86_64-linux-gnu/ /lib/x86_64-linux-gnu/

COPY scripts/ /app/osm_mon/scripts/

# Creating the user for the app
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g 1000 -d /app appuser && \
    mkdir -p /app/osm_mon && \
    mkdir -p /app/storage/kafka && \
    mkdir /app/log && \
    chown -R appuser:appuser /app

WORKDIR /app/osm_mon

# Changing the security context
USER appuser

########################################################################

ENV OSMMON_MESSAGE_DRIVER kafka
ENV OSMMON_MESSAGE_HOST kafka
ENV OSMMON_MESSAGE_PORT 9092

ENV OSMMON_DATABASE_DRIVER mongo
ENV OSMMON_DATABASE_URI mongodb://mongo:27017

ENV OSMMON_SQL_DATABASE_URI sqlite:///mon_sqlite.db
ENV OSMMON_OPENSTACK_DEFAULT_GRANULARITY 300
ENV OSMMON_GLOBAL_REQUEST_TIMEOUT 10
ENV OSMMON_GLOBAL_LOGLEVEL INFO
ENV OSMMON_VCA_HOST localhost
ENV OSMMON_VCA_SECRET secret
ENV OSMMON_VCA_USER admin
ENV OSMMON_VCA_CACERT cacert
ENV OSMMON_DATABASE_COMMONKEY changeme
ENV OSMMON_COLLECTOR_INTERVAL 30
ENV OSMMON_EVALUATOR_INTERVAL 30
ENV OSMMON_PROMETHEUS_URL http://prometheus:9090
ENV OSMMON_GRAFANA_URL http://grafana:3000
ENV OSMMON_GRAFANA_USER admin
ENV OSMMON_GRAFANA_PASSWORD admin

EXPOSE 8000

HEALTHCHECK --start-period=120s --interval=5s --timeout=2s --retries=12\
  CMD osm-mon-healthcheck || exit 1

CMD /bin/bash scripts/dashboarder-start.sh
