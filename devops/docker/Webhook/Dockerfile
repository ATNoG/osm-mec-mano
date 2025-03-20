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

ARG PYTHON3_OSM_WEBHOOK_TRANSLATOR_URL

RUN curl $PYTHON3_OSM_WEBHOOK_TRANSLATOR_URL -o osm_webhook_translator.deb
RUN dpkg -i ./osm_webhook_translator.deb

RUN pip3 install \
    -r /usr/lib/python3/dist-packages/osm_webhook_translator/requirements.txt

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
COPY --from=INSTALL /usr/local/lib/python3.10/dist-packages /usr/local/lib/python3.10/dist-packages

#######################################################################################
# End of common preparation

RUN rm -f /etc/apt/apt.conf.d/proxy.conf

COPY --from=INSTALL /usr/local/bin/uvicorn /usr/local/bin/uvicorn

# Creating the user for the app
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g 1000 -d /app appuser && \
    mkdir -p /app/osm_webhook_translator && \
    chown -R appuser:appuser /app

WORKDIR /app/osm_webhook_translator

# Changing the security context
USER appuser

EXPOSE 9998

CMD ["uvicorn", "osm_webhook_translator.main:app", "--host", "0.0.0.0", "--port", "9998"]

