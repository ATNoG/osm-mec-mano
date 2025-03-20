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

FROM apache/airflow:2.5.3-python3.10
USER root
RUN DEBIAN_FRONTEND=noninteractive apt-get --yes update && \
    DEBIAN_FRONTEND=noninteractive apt-get --yes install \
    gcc git python3 python3-dev python3-venv python3-pip \
    python3-setuptools wget zstd && \
    python3 -m pip install -U pip build

USER airflow

ARG PYTHON3_OSM_COMMON_URL
ARG PYTHON3_OSM_NGSA_URL
RUN curl $PYTHON3_OSM_COMMON_URL -o osm_common.deb
RUN curl $PYTHON3_OSM_NGSA_URL -o osm_ngsa.deb

RUN ar x osm_common.deb && \
    zstd -d < control.tar.zst | xz > control.tar.xz && \
    zstd -d < data.tar.zst | xz > data.tar.xz && \
    ar -m -c -a sdsd osm_common_repacked.deb debian-binary control.tar.xz data.tar.xz && \
    rm debian-binary control.tar.xz data.tar.xz control.tar.zst data.tar.zst
RUN ar x osm_ngsa.deb && \
   zstd -d < control.tar.zst | xz > control.tar.xz && \
   zstd -d < data.tar.zst | xz > data.tar.xz && \
   ar -m -c -a sdsd osm_ngsa_repacked.deb debian-binary control.tar.xz data.tar.xz && \
   rm debian-binary control.tar.xz data.tar.xz control.tar.zst data.tar.zst

RUN mkdir /tmp/osm
RUN dpkg-deb -x osm_common_repacked.deb /tmp/osm
RUN dpkg-deb -x osm_ngsa_repacked.deb /tmp/osm
RUN mv /tmp/osm/usr/lib/python3/dist-packages/* /home/airflow/.local/lib/python3.10/site-packages/
RUN rm -rf /tmp/osm

RUN pip3 install \
   -r /home/airflow/.local/lib/python3.10/site-packages/osm_common/requirements.txt \
   -r /home/airflow/.local/lib/python3.10/site-packages/osm_ngsa/requirements.txt

