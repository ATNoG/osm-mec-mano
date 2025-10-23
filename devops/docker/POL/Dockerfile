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
    mysql-client-core-8.0=8.0.*

ARG PYTHON3_OSM_COMMON_URL
ARG PYTHON3_OSM_POLICY_MODULE_URL

RUN curl $PYTHON3_OSM_COMMON_URL -o osm_common.deb
RUN dpkg -i ./osm_common.deb

RUN curl $PYTHON3_OSM_POLICY_MODULE_URL -o osm_policy_module.deb
RUN dpkg -i ./osm_policy_module.deb

RUN pip3 install \
    -r /usr/lib/python3/dist-packages/osm_common/requirements.txt \
    -r /usr/lib/python3/dist-packages/osm_policy_module/requirements.txt

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

COPY --from=INSTALL /usr/bin/osm* /usr/bin/
COPY --from=INSTALL /usr/bin/mysql /usr/bin/
COPY --from=INSTALL /usr/bin/mysqladmin /usr/bin/
COPY --from=INSTALL /usr/bin/mysqlshow /usr/bin/
COPY --from=INSTALL /usr/lib/x86_64-linux-gnu/libedit.so.2 /usr/lib/x86_64-linux-gnu/
COPY --from=INSTALL /usr/lib/x86_64-linux-gnu/libbsd.so.0 /usr/lib/x86_64-linux-gnu/
COPY --from=INSTALL /usr/lib/x86_64-linux-gnu/libmd.so.0 /usr/lib/x86_64-linux-gnu/

COPY scripts/ /app/osm_pol/scripts/

# Creating the user for the app
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g 1000 -d /app appuser && \
    mkdir -p /app/osm_pol && \
    mkdir -p /app/storage/kafka && \
    mkdir /app/log && \
    chown -R appuser:appuser /app

WORKDIR /app/osm_pol

# Changing the security context
USER appuser

########################################################################

ENV OSMPOL_MESSAGE_DRIVER kafka
ENV OSMPOL_MESSAGE_HOST kafka
ENV OSMPOL_MESSAGE_PORT 9092

ENV OSMPOL_DATABASE_DRIVER mongo
ENV OSMPOL_DATABASE_URI mongodb://mongo:27017

ENV OSMPOL_SQL_DATABASE_URI sqlite:///mon_sqlite.db

ENV OSMPOL_GLOBAL_LOG_LEVEL INFO

ENV OSMPOL_AUTOHEAL_ENABLED True

ENV OSMPOL_AUTOSCALE_ENABLED True

HEALTHCHECK --start-period=120s --interval=10s --timeout=5s --retries=5 \
  CMD osm-pol-healthcheck || exit 1

CMD /bin/bash scripts/start.sh
