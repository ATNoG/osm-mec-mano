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
    apt-transport-https=2.4.* \
    curl=7.81.* \
    gnupg2=2.2.* \
    nginx=1.18.* \
    software-properties-common=0.99.* \
    xz-utils=5.2.* \
    && rm -rf /var/lib/apt/lists/*

RUN curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - && \
    echo "deb https://deb.nodesource.com/node_14.x jammy main" | tee -a /etc/apt/sources.list.d/nodesource.list && \
    DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs

ARG OSM_NGUI_URL

RUN curl $OSM_NGUI_URL -o osm_ngui.deb
RUN dpkg -i ./osm_ngui.deb

WORKDIR /usr/share/osm-ngui
RUN npm install

# Building app.
RUN npm run build

#######################################################################################
FROM ubuntu:22.04 AS FINAL

ARG APT_PROXY
RUN if [ ! -z $APT_PROXY ] ; then \
    echo "Acquire::http::Proxy \"$APT_PROXY\";" > /etc/apt/apt.conf.d/proxy.conf ;\
    echo "Acquire::https::Proxy \"$APT_PROXY\";" >> /etc/apt/apt.conf.d/proxy.conf ;\
    fi

RUN DEBIAN_FRONTEND=noninteractive apt-get --yes update && \
    DEBIAN_FRONTEND=noninteractive apt-get --yes install \
    nginx=1.18.* && \
    rm -rf /var/lib/apt/lists/*

RUN rm -f /etc/apt/apt.conf.d/proxy.conf

# Removing the Nginx default page.
RUN rm -rf /usr/share/nginx/html/*

# Copying Nginx configuration
COPY --from=INSTALL /usr/share/osm-ngui/nginx/nginx.conf /etc/nginx/sites-available/default

# Copying angular build to Nginx default page.
COPY --from=INSTALL /usr/share/osm-ngui/dist/osm /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --start-period=130s --interval=10s --timeout=5s --retries=12 \
  CMD curl --silent --fail localhost:80 || exit 1

# Starting server.
CMD ["nginx", "-g", "daemon off;"]
