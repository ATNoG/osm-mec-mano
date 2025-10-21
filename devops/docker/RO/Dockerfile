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
    genisoimage=9:1.1.* \
    libmagic1 \
    netbase=6.*

ARG PYTHON3_OSM_COMMON_URL
ARG PYTHON3_OSM_NG_RO_URL
ARG PYTHON3_OSM_RO_PLUGIN_URL
ARG PYTHON3_OSM_ROSDN_ARISTA_CLOUDVISION_URL
ARG PYTHON3_OSM_ROSDN_DPB_URL
ARG PYTHON3_OSM_ROSDN_DYNPAC_URL
ARG PYTHON3_OSM_ROSDN_FLOODLIGHTOF_URL
ARG PYTHON3_OSM_ROSDN_IETFL2VPN_URL
ARG PYTHON3_OSM_ROSDN_JUNIPER_CONTRAIL_URL
ARG PYTHON3_OSM_ROSDN_ODLOF_URL
ARG PYTHON3_OSM_ROSDN_ONOSOF_URL
ARG PYTHON3_OSM_ROSDN_ONOS_VPLS_URL
ARG PYTHON3_OSM_ROVIM_AWS_URL
ARG PYTHON3_OSM_ROVIM_AZURE_URL
ARG PYTHON3_OSM_ROVIM_GCP_URL
ARG PYTHON3_OSM_ROVIM_OPENSTACK_URL
ARG PYTHON3_OSM_ROVIM_OPENVIM_URL
ARG PYTHON3_OSM_ROVIM_VCENTER_URL
ARG PYTHON3_OSM_ROVIM_VMWARE_URL

RUN for URL in \
    $PYTHON3_OSM_COMMON_URL \
    $PYTHON3_OSM_NG_RO_URL \
    $PYTHON3_OSM_RO_PLUGIN_URL \
    $PYTHON3_OSM_ROSDN_ARISTA_CLOUDVISION_URL \
    $PYTHON3_OSM_ROSDN_DPB_URL \
    $PYTHON3_OSM_ROSDN_DYNPAC_URL \
    $PYTHON3_OSM_ROSDN_FLOODLIGHTOF_URL \
    $PYTHON3_OSM_ROSDN_IETFL2VPN_URL \
    $PYTHON3_OSM_ROSDN_JUNIPER_CONTRAIL_URL \
    $PYTHON3_OSM_ROSDN_ODLOF_URL \
    $PYTHON3_OSM_ROSDN_ONOSOF_URL \
    $PYTHON3_OSM_ROSDN_ONOS_VPLS_URL \
    $PYTHON3_OSM_ROVIM_AWS_URL \
    $PYTHON3_OSM_ROVIM_AZURE_URL \
    $PYTHON3_OSM_ROVIM_GCP_URL \
    $PYTHON3_OSM_ROVIM_OPENSTACK_URL \
    $PYTHON3_OSM_ROVIM_OPENVIM_URL \
    $PYTHON3_OSM_ROVIM_VCENTER_URL \
    $PYTHON3_OSM_ROVIM_VMWARE_URL ; do \
        curl -s $URL -O ; \
    done

RUN dpkg -i *.deb

RUN pip3 install \
    -r /usr/lib/python3/dist-packages/osm_common/requirements.txt \
    -r /usr/lib/python3/dist-packages/osm_ng_ro/requirements.txt

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

RUN rm -f /etc/apt/apt.conf.d/proxy.conf

COPY --from=INSTALL /usr/bin/genisoimage /usr/bin/genisoimage
COPY --from=INSTALL /etc/protocols /etc/protocols

# Copy libmagic.so.1 and dependencies
COPY --from=INSTALL /usr/lib/x86_64-linux-gnu/libmagic.so.1 /usr/lib/x86_64-linux-gnu/
COPY --from=INSTALL /usr/lib/x86_64-linux-gnu/libmagic.so.1.* /usr/lib/x86_64-linux-gnu/
COPY --from=INSTALL /usr/share/misc/magic.mgc /usr/share/misc/magic.mgc

EXPOSE 9090

# Creating the user for the app
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g 1000 -d /app appuser && \
    mkdir -p /app/osm_ro && \
    mkdir -p /app/storage/kafka && \
    mkdir /app/log && \
    chown -R appuser:appuser /app

WORKDIR /app/osm_ro

# Changing the security context
USER appuser

# Two mysql databases are needed (DB and DB_OVIM). Can be hosted on same or separated containers
# These ENV must be provided
ENV RO_DB_HOST=""
ENV RO_DB_OVIM_HOST=""
    # if empty RO_DB_HOST is assumed

# These ENV should be provided first time for creating database. It will create and init only if empty!
ENV RO_DB_ROOT_PASSWORD=""
ENV RO_DB_OVIM_ROOT_PASSWORD=""
    # if empty RO_DB_ROOT_PASSWORD is assumed

# These ENV can be provided, but default values are ok
ENV RO_DB_USER=mano
ENV RO_DB_OVIM_USER=mano
ENV RO_DB_PASSWORD=manopw
ENV RO_DB_OVIM_PASSWORD=manopw
ENV RO_DB_PORT=3306
ENV RO_DB_OVIM_PORT=3306
ENV RO_DB_NAME=mano_db
ENV RO_DB_OVIM_NAME=mano_vim_db
ENV OPENMANO_TENANT=osm

# database
ENV OSMRO_DATABASE_DRIVER mongo
ENV OSMRO_DATABASE_URI mongodb://mongo:27017
# ENV OSMRO_DATABASE_COMMONKEY  xxx
# ENV OSMRO_DATABASE_USER  xxx
# ENV OSMRO_DATABASE_PASSWORD  xxx

# message
ENV OSMRO_MESSAGE_DRIVER  kafka
ENV OSMRO_MESSAGE_HOST    kafka
ENV OSMRO_MESSAGE_PORT    9092

# logs
ENV OSMRO_LOG_LEVEL       INFO

HEALTHCHECK --start-period=130s --interval=10s --timeout=5s --retries=12 \
  CMD curl --silent --fail http://localhost:9090/ro || exit 1

CMD ["python3", "-u", "-m", "osm_ng_ro.ro_main"]
