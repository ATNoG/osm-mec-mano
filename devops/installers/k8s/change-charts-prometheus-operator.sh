#!/bin/bash

#   Copyright 2019 Minsait - Indra S.A.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#   Author: Jose Manuel Palacios (jmpalacios@minsait.com)
#   Author: Jose Antonio Martinez (jamartinezv@minsait.com)

# Script to generate new charts for kube-prometheus-stack
HERE=$(dirname $(readlink -f ${BASH_SOURCE[0]}))
source $HERE/versions_monitoring
V_OPERATOR=""

# Assign versions
V_OPERATOR=$PROMETHEUS_OPERATOR

WORK_DIR=$HERE
CHARTS_DIR="$HERE/helm_charts"
mkdir -p $CHARTS_DIR


# Delete old versions
cd $CHARTS_DIR

rm -rf kube-prometheus-stack > /dev/null 2>&1 
rm kube-prometheus-stack* > /dev/null 2>&1 

echo "Fetching prometheus-community/kube-prometheus-stack..."
helm fetch --version=$V_OPERATOR prometheus-community/kube-prometheus-stack
tar xvf kube-prometheus-stack-$V_OPERATOR.tgz > /dev/null 2>&1
cd $WORK_DIR


# Patching Grafana dashboards
cd $CHARTS_DIR/kube-prometheus-stack/templates/grafana/dashboards-1.14
for f in $(find . -name '*.yaml*');
do
    # Set the correct datasource in all dashboards
    linenumber=`cat -n $f | grep -A8 '"name": "datasource"' | grep regex | awk '{print $1}'`
    sed -e "$linenumber s/\"regex\": \"\"/\"regex\": \"Prometheus\"/" -i $f
done
cd $WORK_DIR


exit 0
