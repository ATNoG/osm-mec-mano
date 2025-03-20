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


import yaml
import base64


def gather_age_key(cluster):
    pubkey = cluster.get("age_pubkey")
    privkey = cluster.get("age_privkey")
    # return both public and private key
    return pubkey, privkey


async def create_cluster(self, op_id, op_params, content):
    self.logger.info(f"create_cluster Enter. Operation {op_id}. Params: {op_params}")
    # self.logger.debug(f"Content: {content}")

    db_cluster = content["cluster"]
    db_vim_account = content["vim_account"]

    workflow_template = "launcher-create-crossplane-cluster-and-bootstrap.j2"
    workflow_name = f"create-cluster-{db_cluster['_id']}"
    cluster_name = db_cluster["git_name"].lower()

    # Get age key
    public_key_new_cluster, private_key_new_cluster = gather_age_key(db_cluster)
    # self.logger.debug(f"public_key_new_cluster={public_key_new_cluster}")
    # self.logger.debug(f"private_key_new_cluster={private_key_new_cluster}")

    # Test kubectl connection
    self.logger.debug(f"Testing kubectl: {self._kubectl}")
    self.logger.debug(f"Testing kubectl configuration: {self._kubectl.configuration}")
    self.logger.debug(
        f"Testing kubectl configuration Host: {self._kubectl.configuration.host}"
    )
    self.logger.debug(self._kubectl._get_kubectl_version())

    # Create temporal secret with agekey
    secret_name = f"secret-age-{cluster_name}"
    secret_namespace = "osm-workflows"
    secret_key = "agekey"
    secret_value = private_key_new_cluster
    try:
        self.logger.debug(f"Testing kubectl: {self._kubectl}")
        self.logger.debug(
            f"Testing kubectl configuration: {self._kubectl.configuration}"
        )
        self.logger.debug(
            f"Testing kubectl configuration Host: {self._kubectl.configuration.host}"
        )
        await self.create_secret(
            secret_name,
            secret_namespace,
            secret_key,
            secret_value,
        )
    except Exception as e:
        self.logger.info(f"Cannot create secret {secret_name}: {e}")
        return False, f"Cannot create secret {secret_name}: {e}"

    # Additional params for the workflow
    cluster_kustomization_name = cluster_name
    osm_project_name = "osm_admin"  # TODO: get project name from content
    vim_account_id = db_cluster["vim_account"]
    providerconfig_name = f"{vim_account_id}-config"
    vim_type = db_vim_account["vim_type"]
    if db_cluster.get("bootstrap", True):
        skip_bootstrap = "false"
    else:
        skip_bootstrap = "true"
    if vim_type == "azure":
        cluster_type = "aks"
    elif vim_type == "aws":
        cluster_type = "eks"
    elif vim_type == "gcp":
        cluster_type = "gke"
    else:
        raise Exception("Not suitable VIM account to register cluster")

    # Render workflow
    # workflow_kwargs = {
    #     "git_fleet_url": f"{self._repo_base_url}/{self._repo_user}/fleet-osm.git",
    #     "git_sw_catalogs_url": f"{self._repo_base_url}/{self._repo_user}/sw-catalogs-osm.git",
    # }
    # manifest = self.render_jinja_template(
    #     workflow_template,
    #     output_file=None,
    #     **workflow_kwargs
    # )
    manifest = self.render_jinja_template(
        workflow_template,
        output_file=None,
        workflow_name=workflow_name,
        git_fleet_url=f"{self._repo_base_url}/{self._repo_user}/fleet-osm.git",
        git_sw_catalogs_url=f"{self._repo_base_url}/{self._repo_user}/sw-catalogs-osm.git",
        cluster_name=cluster_name,
        cluster_type=cluster_type,
        cluster_kustomization_name=cluster_kustomization_name,
        providerconfig_name=providerconfig_name,
        public_key_mgmt=self._pubkey,
        public_key_new_cluster=public_key_new_cluster,
        secret_name_private_key_new_cluster=secret_name,
        vm_size=db_cluster["node_size"],
        node_count=db_cluster["node_count"],
        k8s_version=db_cluster["k8s_version"],
        cluster_location=db_cluster["region_name"],
        osm_project_name=osm_project_name,
        rg_name=db_cluster.get("resource_group", "''"),
        preemptible_nodes=db_cluster.get("preemptible_nodes", "false"),
        skip_bootstrap=skip_bootstrap,
        workflow_debug=self._workflow_debug,
        workflow_dry_run=self._workflow_dry_run,
    )
    self.logger.debug(f"Workflow manifest: {manifest}")

    # Submit workflow
    self.logger.debug(f"Testing kubectl: {self._kubectl}")
    self.logger.debug(f"Testing kubectl configuration: {self._kubectl.configuration}")
    self.logger.debug(
        f"Testing kubectl configuration Host: {self._kubectl.configuration.host}"
    )
    self._kubectl.create_generic_object(
        namespace="osm-workflows",
        manifest_dict=yaml.safe_load(manifest),
        api_group="argoproj.io",
        api_plural="workflows",
        api_version="v1alpha1",
    )
    return True, workflow_name


async def update_cluster(self, op_id, op_params, content):
    self.logger.info(f"update_cluster Enter. Operation {op_id}. Params: {op_params}")
    # self.logger.debug(f"Content: {content}")

    db_cluster = content["cluster"]
    db_vim_account = content["vim_account"]
    cluster_name = db_cluster["git_name"].lower()

    workflow_template = "launcher-update-crossplane-cluster.j2"
    workflow_name = f"update-cluster-{op_id}"
    # cluster_name = db_cluster["name"].lower()

    # Get age key
    public_key_cluster, private_key_cluster = gather_age_key(db_cluster)
    self.logger.debug(f"public_key_new_cluster={public_key_cluster}")
    self.logger.debug(f"private_key_new_cluster={private_key_cluster}")

    # Create secret with agekey
    secret_name = f"secret-age-{cluster_name}"
    secret_namespace = "osm-workflows"
    secret_key = "agekey"
    secret_value = private_key_cluster
    try:
        self.logger.debug(f"Testing kubectl: {self._kubectl}")
        self.logger.debug(
            f"Testing kubectl configuration: {self._kubectl.configuration}"
        )
        self.logger.debug(
            f"Testing kubectl configuration Host: {self._kubectl.configuration.host}"
        )
        await self.create_secret(
            secret_name,
            secret_namespace,
            secret_key,
            secret_value,
        )
    except Exception as e:
        self.logger.info(f"Cannot create secret {secret_name}: {e}")
        return False, f"Cannot create secret {secret_name}: {e}"

    # Additional params for the workflow
    cluster_kustomization_name = cluster_name
    osm_project_name = "osm_admin"  # TODO: get project name from db_cluster
    vim_account_id = db_cluster["vim_account"]
    providerconfig_name = f"{vim_account_id}-config"
    vim_type = db_vim_account["vim_type"]
    vm_size = op_params.get("node_size", db_cluster["node_size"])
    node_count = op_params.get("node_count", db_cluster["node_count"])
    k8s_version = op_params.get("k8s_version", db_cluster["k8s_version"])
    if vim_type == "azure":
        cluster_type = "aks"
    elif vim_type == "aws":
        cluster_type = "eks"
    elif vim_type == "gcp":
        cluster_type = "gke"
    else:
        raise Exception("Not suitable VIM account to update cluster")

    # Render workflow
    manifest = self.render_jinja_template(
        workflow_template,
        output_file=None,
        workflow_name=workflow_name,
        git_fleet_url=f"{self._repo_base_url}/{self._repo_user}/fleet-osm.git",
        git_sw_catalogs_url=f"{self._repo_base_url}/{self._repo_user}/sw-catalogs-osm.git",
        cluster_name=cluster_name,
        cluster_type=cluster_type,
        cluster_kustomization_name=cluster_kustomization_name,
        providerconfig_name=providerconfig_name,
        public_key_mgmt=self._pubkey,
        public_key_new_cluster=public_key_cluster,
        secret_name_private_key_new_cluster=secret_name,
        vm_size=vm_size,
        node_count=node_count,
        k8s_version=k8s_version,
        cluster_location=db_cluster["region_name"],
        osm_project_name=osm_project_name,
        rg_name=db_cluster.get("resource_group", "''"),
        preemptible_nodes=db_cluster.get("preemptible_nodes", "false"),
        workflow_debug=self._workflow_debug,
        workflow_dry_run=self._workflow_dry_run,
    )
    self.logger.info(manifest)

    # Submit workflow
    self.logger.debug(f"Testing kubectl: {self._kubectl}")
    self.logger.debug(f"Testing kubectl configuration: {self._kubectl.configuration}")
    self.logger.debug(
        f"Testing kubectl configuration Host: {self._kubectl.configuration.host}"
    )
    self._kubectl.create_generic_object(
        namespace="osm-workflows",
        manifest_dict=yaml.safe_load(manifest),
        api_group="argoproj.io",
        api_plural="workflows",
        api_version="v1alpha1",
    )
    return True, workflow_name


async def delete_cluster(self, op_id, op_params, content):
    self.logger.info(f"delete_cluster Enter. Operation {op_id}. Params: {op_params}")
    # self.logger.debug(f"Content: {content}")

    db_cluster = content["cluster"]

    workflow_template = "launcher-delete-cluster.j2"
    workflow_name = f"delete-cluster-{db_cluster['_id']}"
    # cluster_name = db_cluster["name"].lower()
    cluster_name = db_cluster["git_name"].lower()

    # Additional params for the workflow
    cluster_kustomization_name = cluster_name
    osm_project_name = "osm_admin"  # TODO: get project name from DB

    # Render workflow
    manifest = self.render_jinja_template(
        workflow_template,
        output_file=None,
        workflow_name=workflow_name,
        git_fleet_url=f"{self._repo_base_url}/{self._repo_user}/fleet-osm.git",
        git_sw_catalogs_url=f"{self._repo_base_url}/{self._repo_user}/sw-catalogs-osm.git",
        cluster_name=cluster_name,
        cluster_kustomization_name=cluster_kustomization_name,
        osm_project_name=osm_project_name,
        workflow_debug=self._workflow_debug,
        workflow_dry_run=self._workflow_dry_run,
    )
    self.logger.info(manifest)

    # Submit workflow
    self.logger.debug(f"Testing kubectl: {self._kubectl}")
    self.logger.debug(f"Testing kubectl configuration: {self._kubectl.configuration}")
    self.logger.debug(
        f"Testing kubectl configuration Host: {self._kubectl.configuration.host}"
    )
    self._kubectl.create_generic_object(
        namespace="osm-workflows",
        manifest_dict=yaml.safe_load(manifest),
        api_group="argoproj.io",
        api_plural="workflows",
        api_version="v1alpha1",
    )
    return True, workflow_name


async def register_cluster(self, op_id, op_params, content):
    self.logger.info(f"register_cluster Enter. Operation {op_id}. Params: {op_params}")
    # self.logger.debug(f"Content: {content}")

    db_cluster = content["cluster"]
    cluster_name = db_cluster["git_name"].lower()

    workflow_template = "launcher-bootstrap-cluster.j2"
    workflow_name = f"register-cluster-{db_cluster['_id']}"

    # Get age key
    public_key_new_cluster, private_key_new_cluster = gather_age_key(db_cluster)
    self.logger.debug(f"public_key_new_cluster={public_key_new_cluster}")
    self.logger.debug(f"private_key_new_cluster={private_key_new_cluster}")

    # Create temporal secret with agekey
    secret_name = f"secret-age-{cluster_name}"
    secret_namespace = "osm-workflows"
    secret_key = "agekey"
    secret_value = private_key_new_cluster
    try:
        self.logger.debug(f"Testing kubectl: {self._kubectl}")
        self.logger.debug(
            f"Testing kubectl configuration: {self._kubectl.configuration}"
        )
        self.logger.debug(
            f"Testing kubectl configuration Host: {self._kubectl.configuration.host}"
        )
        await self.create_secret(
            secret_name,
            secret_namespace,
            secret_key,
            secret_value,
        )
    except Exception as e:
        self.logger.info(
            f"Cannot create secret {secret_name} in namespace {secret_namespace}: {e}"
        )
        return (
            False,
            f"Cannot create secret {secret_name} in namespace {secret_namespace}: {e}",
        )

    # Create secret with kubeconfig
    secret_name2 = f"kubeconfig-{cluster_name}"
    secret_namespace2 = "managed-resources"
    secret_key2 = "kubeconfig"
    secret_value2 = yaml.safe_dump(
        db_cluster["credentials"], indent=2, default_flow_style=False, sort_keys=False
    )
    try:
        self.logger.debug(f"Testing kubectl: {self._kubectl}")
        self.logger.debug(
            f"Testing kubectl configuration: {self._kubectl.configuration}"
        )
        self.logger.debug(
            f"Testing kubectl configuration Host: {self._kubectl.configuration.host}"
        )
        await self.create_secret(
            secret_name2,
            secret_namespace2,
            secret_key2,
            secret_value2,
        )
    except Exception as e:
        self.logger.info(
            f"Cannot create secret {secret_name} in namespace {secret_namespace}: {e}"
        )
        return (
            False,
            f"Cannot create secret {secret_name} in namespace {secret_namespace}: {e}",
        )

    # Additional params for the workflow
    cluster_kustomization_name = cluster_name
    osm_project_name = "osm_admin"  # TODO: get project name from content

    manifest = self.render_jinja_template(
        workflow_template,
        output_file=None,
        workflow_name=workflow_name,
        git_fleet_url=f"{self._repo_base_url}/{self._repo_user}/fleet-osm.git",
        git_sw_catalogs_url=f"{self._repo_base_url}/{self._repo_user}/sw-catalogs-osm.git",
        cluster_name=cluster_name,
        cluster_kustomization_name=cluster_kustomization_name,
        public_key_mgmt=self._pubkey,
        public_key_new_cluster=public_key_new_cluster,
        secret_name_private_key_new_cluster=secret_name,
        osm_project_name=osm_project_name,
        workflow_debug=self._workflow_debug,
        workflow_dry_run=self._workflow_dry_run,
    )
    self.logger.debug(f"Workflow manifest: {manifest}")

    # Submit workflow
    self.logger.debug(f"Testing kubectl: {self._kubectl}")
    self.logger.debug(f"Testing kubectl configuration: {self._kubectl.configuration}")
    self.logger.debug(
        f"Testing kubectl configuration Host: {self._kubectl.configuration.host}"
    )
    self._kubectl.create_generic_object(
        namespace="osm-workflows",
        manifest_dict=yaml.safe_load(manifest),
        api_group="argoproj.io",
        api_plural="workflows",
        api_version="v1alpha1",
    )
    return True, workflow_name


async def deregister_cluster(self, op_id, op_params, content):
    self.logger.info(
        f"deregister_cluster Enter. Operation {op_id}. Params: {op_params}"
    )
    # self.logger.debug(f"Content: {content}")

    db_cluster = content["cluster"]
    cluster_name = db_cluster["git_name"].lower()

    workflow_template = "launcher-disconnect-flux-remote-cluster.j2"
    workflow_name = f"deregister-cluster-{db_cluster['_id']}"

    # Additional params for the workflow
    cluster_kustomization_name = cluster_name
    osm_project_name = "osm_admin"  # TODO: get project name from DB

    # Render workflow
    manifest = self.render_jinja_template(
        workflow_template,
        output_file=None,
        workflow_name=workflow_name,
        git_fleet_url=f"{self._repo_base_url}/{self._repo_user}/fleet-osm.git",
        cluster_kustomization_name=cluster_kustomization_name,
        osm_project_name=osm_project_name,
        workflow_debug=self._workflow_debug,
        workflow_dry_run=self._workflow_dry_run,
    )
    self.logger.info(manifest)

    # Submit workflow
    self.logger.debug(f"Testing kubectl: {self._kubectl}")
    self.logger.debug(f"Testing kubectl configuration: {self._kubectl.configuration}")
    self.logger.debug(
        f"Testing kubectl configuration Host: {self._kubectl.configuration.host}"
    )
    self._kubectl.create_generic_object(
        namespace="osm-workflows",
        manifest_dict=yaml.safe_load(manifest),
        api_group="argoproj.io",
        api_plural="workflows",
        api_version="v1alpha1",
    )
    return True, workflow_name


async def get_cluster_credentials(self, db_cluster):
    """
    returns the kubeconfig file of a K8s cluster in a dictionary
    """
    self.logger.info("get_cluster_credentials Enter")
    # self.logger.debug(f"Content: {db_cluster}")

    secret_name = f"kubeconfig-{db_cluster['git_name'].lower()}"
    secret_namespace = "managed-resources"
    secret_key = "kubeconfig"

    self.logger.info(f"Checking content of secret {secret_name} ...")
    try:
        returned_secret_data = await self._kubectl.get_secret_content(
            name=secret_name,
            namespace=secret_namespace,
        )
        returned_secret_value = base64.b64decode(
            returned_secret_data[secret_key]
        ).decode("utf-8")
        return True, yaml.safe_load(returned_secret_value)
    except Exception as e:
        message = f"Not possible to get the credentials of the cluster. Exception: {e}"
        self.logger.critical(message)
        return False, message


async def clean_items_cluster_create(self, op_id, op_params, content):
    self.logger.info(
        f"clean_items_cluster_create Enter. Operation {op_id}. Params: {op_params}"
    )
    self.logger.debug(f"Content: {content}")
    items = {
        "secrets": [
            {
                "name": f"secret-age-{content['cluster']['git_name'].lower()}",
                "namespace": "osm-workflows",
            }
        ]
    }
    try:
        await self.clean_items(items)
        return True, "OK"
    except Exception as e:
        return False, f"Error while cleaning items: {e}"


async def clean_items_cluster_update(self, op_id, op_params, content):
    self.logger.info(
        f"clean_items_cluster_update Enter. Operation {op_id}. Params: {op_params}"
    )
    # self.logger.debug(f"Content: {content}")
    return await self.clean_items_cluster_create(op_id, op_params, content)


async def clean_items_cluster_register(self, op_id, op_params, content):
    self.logger.info(
        f"clean_items_cluster_register Enter. Operation {op_id}. Params: {op_params}"
    )
    # self.logger.debug(f"Content: {content}")
    # Clean secrets
    cluster_name = content["cluster"]["git_name"].lower()
    items = {
        "secrets": [
            {
                "name": f"secret-age-{cluster_name}",
                "namespace": "osm-workflows",
            },
        ]
    }

    try:
        await self.clean_items(items)
        return True, "OK"
    except Exception as e:
        return False, f"Error while cleaning items: {e}"


async def clean_items_cluster_deregister(self, op_id, op_params, content):
    self.logger.info(
        f"clean_items_cluster_deregister Enter. Operation {op_id}. Params: {op_params}"
    )
    # self.logger.debug(f"Content: {content}")
    # Clean secrets
    self.logger.info("Cleaning kubeconfig")
    cluster_name = content["cluster"]["git_name"].lower()
    items = {
        "secrets": [
            {
                "name": f"kubeconfig-{cluster_name}",
                "namespace": "managed-resources",
            },
        ]
    }

    try:
        await self.clean_items(items)
        return True, "OK"
    except Exception as e:
        return False, f"Error while cleaning items: {e}"
