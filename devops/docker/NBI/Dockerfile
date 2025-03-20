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
ARG PYTHON3_OSM_IM_URL
ARG PYTHON3_OSM_NBI_URL

RUN curl $PYTHON3_OSM_COMMON_URL -o osm_common.deb
RUN dpkg -i ./osm_common.deb

RUN curl $PYTHON3_OSM_IM_URL -o osm_im.deb
RUN dpkg -i ./osm_im.deb

RUN curl $PYTHON3_OSM_NBI_URL -o osm_nbi.deb
RUN dpkg -i ./osm_nbi.deb

RUN pip3 install \
    -r /usr/lib/python3/dist-packages/osm_common/requirements.txt \
    -r /usr/lib/python3/dist-packages/osm_im/requirements.txt \
    -r /usr/lib/python3/dist-packages/osm_nbi/requirements.txt

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

# Creating the user for the app
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g 1000 -d /app appuser && \
    mkdir -p /app/osm_nbi && \
    mkdir -p /app/storage/kafka && \
    mkdir /app/log && \
    chown -R appuser:appuser /app

WORKDIR /app/osm_nbi

# Changing the security context
USER appuser

EXPOSE 9999

RUN cp -R /usr/lib/python3/dist-packages/osm_nbi/html_public /app/osm_nbi/html_public
RUN cp /usr/lib/python3/dist-packages/osm_nbi/nbi.cfg /app/osm_nbi/
RUN cp -R /usr/lib/python3/dist-packages/osm_nbi/http /app/osm_nbi/
RUN cp -R /usr/lib/python3/dist-packages/osm_nbi/templates /app/osm_nbi/templates

# The following ENV can be added with "docker run -e xxx' to configure
# server
ENV OSMNBI_SOCKET_HOST     0.0.0.0
ENV OSMNBI_SOCKET_PORT     9999
# storage
ENV OSMNBI_STORAGE_PATH    /app/storage
# database
ENV OSMNBI_DATABASE_DRIVER mongo
ENV OSMNBI_DATABASE_URI   mongodb://mongo:27017
#ENV OSMNBI_DATABASE_HOST   mongo
#ENV OSMNBI_DATABASE_PORT   27017

# web
ENV OSMNBI_STATIC_DIR      /app/osm_nbi/html_public
# message
ENV OSMNBI_MESSAGE_DRIVER  kafka
ENV OSMNBI_MESSAGE_HOST    kafka
ENV OSMNBI_MESSAGE_PORT    9092
# logs
ENV OSMNBI_LOG_FILE        /app/log/nbi.log
ENV OSMNBI_LOG_LEVEL       DEBUG
# authentication
ENV OSMNBI_AUTHENTICATION_BACKEND               internal
#ENV OSMNBI_AUTHENTICATION_BACKEND               keystone
#ENV OSMNBI_AUTHENTICATION_AUTH_URL              keystone
#ENV OSMNBI_AUTHENTICATION_AUTH_PORT             5000
#ENV OSMNBI_AUTHENTICATION_USER_DOMAIN_NAME      default
#ENV OSMNBI_AUTHENTICATION_PROJECT_DOMAIN_NAME   default
#ENV OSMNBI_AUTHENTICATION_SERVICE_USERNAME      nbi
#ENV OSMNBI_AUTHENTICATION_SERVICE_PASSWORD      nbi
#ENV OSMNBI_AUTHENTICATION_SERVICE_PROJECT       service
#prometheus
ENV OSMNBI_PROMETHEUS_HOST                      prometheus
ENV OSMNBI_PROMETHEUS_PORT                      9090

HEALTHCHECK --start-period=120s --interval=10s --timeout=5s --retries=5 \
  CMD curl -k https://localhost:9999/osm/ | grep Welcome || exit 1

# Run app.py when the container launches
CMD python3 -m osm_nbi.nbi
