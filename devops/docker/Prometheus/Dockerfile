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

FROM python:3.8


ENV PROMETHEUS_URL http://prometheus:9090
ENV MONGODB_URL mongodb://mongo:27017
ENV PROMETHEUS_CONFIG_FILE /etc/prometheus/prometheus.yml
ENV PROMETHEUS_BASE_CONFIG_FILE /etc/prometheus_base/prometheus.yml
ENV PROMETHEUS_ALERTS_FILE /etc/prometheus/osm_alert_rules.yml
ENV PROMETHEUS_BASE_ALERTS_FILE /etc/prometheus_base/osm_alert_rules.yml
ENV TARGET_DATABASE osm

WORKDIR /code

COPY src/requirements.txt .

RUN pip install -r requirements.txt

COPY src/app.py .

CMD [ "python", "-u", "./app.py" ]
