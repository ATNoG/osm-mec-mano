<!--
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
# Gitea

[TOC]

[Gitea](https://gitea.io/en-us/) hosts private git repositories.

[Reference page on GitHub](https://github.com/go-gitea/gitea).

## Installation

### TL;DR

First, select the desired K8s `kubeconfig` and default context where Gitea will be installed.

Then, for an installation with default configuration run:

```bash
./ALL-IN-ONE-Gitea-install.sh
```

For use then you could do:

```bash
source "${CREDENTIALS_DIR}/gitea_environment.rc"
```

For Gitea provisioning for OSM usage (tokens, users and repos), you can just use this script:

```bash
source "${CREDENTIALS_DIR}/gitea_environment.rc"
source "${CREDENTIALS_DIR}/gitea_tokens.rc"
./90-provision-gitea-for-osm.sh"
```

Alternatively, in case you wanted to set up Gitea programmatically for other use cases without using the UI (which is always a possibility), including the setup of Gitea tokens, the creation of users, the creation of repos, etc., you should have a look at all the operations captured in `90-provision-gitea-for-osm.sh` (including the commented examples) and create a custom provisioning script that fits your needs.

For your convenience (although it would not be strictly required), you may also enable the local Git user to interact with the significant repos:

```bash
source "${CREDENTIALS_DIR}/gitea_environment.rc"
source "${CREDENTIALS_DIR}/gitea_tokens.rc"
./91-provision-local-git-user.sh"
```

### Overview of the installation process

This folder provides helper scripts to complete a full standalone installation of Gitea on Kubernetes using the current `kubeconfig` and the current context.

**WARNING:** In case your current `kubeconfig` context does not point to your desired K8s cluster target, simply select it **before** applying any of the scripts:

```bash
export KUBECONFIG=/absolute/path/to/kubeconfig.yaml
kubectl config use-context put-your-desired-context-here
# Alternatively, you may use `kubectx` for interactive selection of your default context
```

Once selected the K8s target, the following environment files and scripts should be applied in the order indicated by their prefix number, noting that `*.rc` files should be sourced and `*.sh` files should be executed. Here is their utility:

- `00-custom-config.rc`: (optional) Used to override selectively some environment variables that may condition the behaviour of the installer scripts. By default, just generates random values for Gitea passwords, but it may edited for further customizations if needed. If not sourced, the rest of scripts will work normally with sensible defaults (note that default passwords will be applied).
- `01-base-config.rc`: Sets sensible defaults to environment variables for Gitea configuration in case they had not been set explicitly before, either via `00-custom-config.rc` or by other means.
- `02-deploy-gitea.sh`: Makes a Gitea installation based on the config variables set in previous steps.
  - It is deployed to the `gitea` namespace using the [published Helm chart](https://docs.gitea.io/en-us/install-on-kubernetes/).
  - Default base Git URLs:
    - The internal base git HTTP URL is `http://gitea-http.gitea:8080`.
    - The internal base git SSH URL is `ssh://gitea-ssh.gitea:22`.
    - If applicable, the exposed (external) base git HTTP URL takes the shape `http://git.${GITEA_HTTP_IP}.nip.io:${GITEA_HTTP_PORT}`, where `${GITEA_HTTP_PORT}` is 8080 by default.
    - If applicable, the exposed (external) base git SSH URL takes the shape `ssh://git.${GITEA_SSH_IP}.nip.io:${GITEA_SSH_PORT}`, where `${GITEA_HTTP_PORT}` is 22 by default.
- `03-get-gitea-connection-info.rc`
- `04-fix-and-use-external-gitea-urls.sh`: (optional) Fixes the base domain of Gitea to point to a `nip.io` URL pointing to the **external** load balancer service IP.
- `05-export-connection-info.sh`: Determines full connection URLs and exports data to `${CREDENTIALS_DIR}` folder and into a K8s secret.
- (optional) `90-provision-gitea-for-osm.sh`: Run post-provisioning tasks in Gitea with scripted operations to support its use from OSM:
  - Create access tokens for the admin and the new standard user.
  - Create new standard user `${GITEA_STD_USERNAME}`.
  - Export tokens to local file in `${CREDENTIALS_DIR}` folder and into a K8s secr
  - Creates default repos for OSM: `fleet-osm` and `sw-catalogs-osm`.
- (optional) `91-provision-local-git-user.sh`: Enable the local Git user to interact with the significant repos supporting its use from OSM:
  - Add the local Git user to Gitea as a profile.
  - Upload the public SSH key (to allow SSH operations).
  - Add the user as _collaborator_ to both repos.

For testing you can use `gitea` in the Gitea main pod via

```bash
./admin/shell.sh
su git
gitea <your_command_goes_here>
```

## Administration

Admin operations on Gitea can be handled in two different ways:

1. Using the `./admin/gitea.sh` script, which wraps the Gitea CLI in the main pod, or
2. Using `./admin/api.sh` to call the [Swagger endpoints](https://try.gitea.io/api/swagger).
   - For these operations you may need the tokens saved at `${CREDENTIALS_DIR}/gitea_tokens.rc` as environment variables ready to be sourced.

In both cases, you will need to source the environment variables saved at `${CREDENTIALS_DIR}/gitea_environment.rc`.

Some common helper scripts for common admin operations are also available in the `./admin/` folder.

You can find many useful (commented) examples of admin operations in `90-provision-gitea-for-osm.sh`.
