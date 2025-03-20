<!--
Copyright 2020 ETSI

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
implied.
See the License for the specific language governing permissions and
limitations under the License
-->
# osm-devops

Scripts and artifacts for OSM installation and CI/CD pipelines.

## Folder structure

- `jenkins`: scripts run by jenkins. All OSM modules rely on these scripts.
- `installers`: scripts to be executed to install OSM. It also includes the OSM helm chart.

## Instructions to test new code in the same way is done in OSM CI/CD pipeline

### Create folder

```bash
mkdir osm
cd osm
```

### Clone projects

Clone the projects that you would like to test

```bash
git clone "https://osm.etsi.org/gerrit/osm/devops"
git clone "https://osm.etsi.org/gerrit/osm/common"
git clone "https://osm.etsi.org/gerrit/osm/N2VC"
git clone "https://osm.etsi.org/gerrit/osm/LCM"
...
```

### Update repos to use a specific branch or a Gerrit patch

If needed, update code in the repos. An example for N2VC is shown below

```bash
cd N2VC
git pull "https://osm.etsi.org/gerrit/osm/N2VC" refs/changes/22/14222/2
cd ..
cd LCM
git pull "https://osm.etsi.org/gerrit/osm/LCM" refs/changes/24/14224/3
cd ..
```

### Start an HTTP server to host the intermediate artifacts (deb packages)

```bash
./devops/tools/local-build.sh --run-httpserver
ps -ef |grep python3
```

### Run stage2 to build artifacts

```bash
# Clean previous artifacts
rm $HOME/.osm/httpd/*.deb
# Build new artifacts
./devops/tools/local-build.sh --module common,N2VC,LCM stage-2
# Check that artifacts were created
ls $HOME/.osm/httpd
```

__Note: Artifacts need to be cleaned every time we want to try new patches__

### Run stage3 to build docker images

```bash
./devops/tools/local-build.sh --module LCM stage-3
docker image ls
# Copy the image to your image resistry, e.g.: "your-registry/osm/osm-testing/opensourcemano/lcm:myfeature"
```

### Update OSM Helm release to use the new image

```bash
helm3 -n osm list
helm3 -n osm get values osm
```

Upgrade with kubectl:

```bash
kubectl -n osm patch deployment lcm --patch '{"spec": {"template": {"spec": {"containers": [{"name": "lcm", "image": "your-registry/osm/osm-testing/opensourcemano/lcm:myfeature}]}}}}'
kubectl -n osm get all
```

Upgrade with Helm:

```bash
helm3 -n osm list
helm3 -n osm history osm
helm3 -n osm upgrade --reuse-values --set lcm.image.repository="your-registry/osm/osm-testing/opensourcemano/lcm" --set lcm.image.tag="myfeature" osm ./helm-chart-dir
helm3 -n osm status osm
kubectl -n osm get all
```

### Test OSM Helm Chart independently

```bash
git clone "https://osm.etsi.org/gerrit/osm/devops"
cd devops/
# Get a patch from Gerrit
# git pull "https://osm.etsi.org/gerrit/osm/devops" refs/changes/25/14325/17
./installers/install_helm_client.sh -D . --debug
./devops-stages/stage-test.sh
./installers/full_install_osm.sh -D . --debug -R testing-daily -t testing-daily -r testing -y  2>&1 | tee osm_install_log.txt
kubectl -n osm get all
kubectl -n osm get ingress
```

