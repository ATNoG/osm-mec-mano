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

ARG PYTHON3_OSM_COMMON_URL
ARG PYTHON3_OSM_PLA_URL

RUN curl $PYTHON3_OSM_COMMON_URL -o osm_common.deb
RUN dpkg -i ./osm_common.deb

RUN curl $PYTHON3_OSM_PLA_URL -o osm_pla.deb
RUN dpkg -i ./osm_pla.deb

RUN pip3 install \
    -r /usr/lib/python3/dist-packages/osm_common/requirements.txt \
    -r /usr/lib/python3/dist-packages/osm_pla/requirements.txt

ADD https://github.com/MiniZinc/MiniZincIDE/releases/download/2.4.2/MiniZincIDE-2.4.2-bundle-linux-x86_64.tgz /minizinc.tgz

RUN tar -zxf /minizinc.tgz && \
    mv /MiniZincIDE-2.4.2-bundle-linux /minizinc

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

RUN rm -f /etc/apt/apt.conf.d/proxy.conf

LABEL authors="Lars-Göran Magnusson"

COPY --from=INSTALL /usr/bin/osm* /usr/bin/
COPY --from=INSTALL /minizinc /minizinc

RUN mkdir /entry_data && \
    mkdir /placement && \
    mkdir /entry_data/mzn-lib && \
    ln -s /entry_data/mzn-lib /minizinc/share/minizinc/exec

COPY scripts/ /app/osm_pla/scripts/

# Creating the user for the app
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g 1000 -d /app appuser && \
    mkdir -p /app/osm_pla && \
    chown -R appuser:appuser /app && \
    chown -R appuser:appuser /entry_data && \
    chown -R appuser:appuser /minizinc && \
    chown -R appuser:appuser /placement

WORKDIR /app/osm_pla

# Changing the security context
USER appuser

ENV OSMPLA_MESSAGE_DRIVER kafka
ENV OSMPLA_MESSAGE_HOST kafka
ENV OSMPLA_MESSAGE_PORT 9092

ENV OSMPLA_DATABASE_DRIVER mongo
ENV OSMPLA_DATABASE_URI mongodb://mongo:27017

ENV OSMPLA_SQL_DATABASE_URI sqlite:///pla_sqlite.db

ENV OSMPLA_GLOBAL_LOG_LEVEL INFO

ENV FZNEXEC "/entry_data/fzn-exec"
ENV PATH "/minizinc/bin:${PATH}"
ENV LD_LIBRARY_PATH "/minizinc/lib:${LD_LIBRARY_PATH}"

# No healtcheck yet...
#HEALTHCHECK --start-period=120s --interval=10s --timeout=5s --retries=5 \
#  CMD osm-pla-healthcheck || exit 1

CMD [ "/bin/bash", "scripts/start.sh" ]
