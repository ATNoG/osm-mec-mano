#######################################################################################
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


import logging
from osm_lcm.lcm_utils import LcmBase
from osm_lcm.n2vc import kubectl


class OduWorkflow(LcmBase):
    def __init__(self, msg, lcm_tasks, config):
        """
        Init, Connect to database, filesystem storage, and messaging
        :param config: two level dictionary with configuration. Top level should contain 'database', 'storage',
        :return: None
        """

        self.logger = logging.getLogger("lcm.gitops")
        self.lcm_tasks = lcm_tasks
        self.logger.info("Msg: {} lcm_tasks: {} ".format(msg, lcm_tasks))

        # self._kubeconfig = kubeconfig  # TODO: get it from config
        self.gitops_config = config["gitops"]
        self.logger.debug(f"Config: {self.gitops_config}")
        self._odu_checkloop_retry_time = 15
        self._kubeconfig = self.gitops_config["mgmtcluster_kubeconfig"]
        self._kubectl = kubectl.Kubectl(config_file=self._kubeconfig)
        self._repo_base_url = self.gitops_config["git_base_url"]
        self._repo_user = self.gitops_config["user"]
        self._pubkey = self.gitops_config["pubkey"]
        self._workflow_debug = str(self.gitops_config["workflow_debug"]).lower()
        self._workflow_dry_run = str(self.gitops_config["workflow_dry_run"]).lower()
        self._workflows = {
            "create_cluster": {
                "workflow_function": self.create_cluster,
                "clean_function": self.clean_items_cluster_create,
            },
            "update_cluster": {
                "workflow_function": self.update_cluster,
                "clean_function": self.clean_items_cluster_update,
            },
            "delete_cluster": {
                "workflow_function": self.delete_cluster,
            },
            "register_cluster": {
                "workflow_function": self.register_cluster,
                "clean_function": self.clean_items_cluster_register,
            },
            "deregister_cluster": {
                "workflow_function": self.deregister_cluster,
                "clean_function": self.clean_items_cluster_deregister,
            },
            "create_profile": {
                "workflow_function": self.create_profile,
            },
            "delete_profile": {
                "workflow_function": self.delete_profile,
            },
            "attach_profile_to_cluster": {
                "workflow_function": self.attach_profile_to_cluster,
            },
            "detach_profile_from_cluster": {
                "workflow_function": self.detach_profile_from_cluster,
            },
            "create_oka": {
                "workflow_function": self.create_oka,
                "clean_function": self.clean_items_oka_create,
            },
            "update_oka": {
                "workflow_function": self.update_oka,
                "clean_function": self.clean_items_oka_update,
            },
            "delete_oka": {
                "workflow_function": self.delete_oka,
                "clean_function": self.clean_items_oka_delete,
            },
            "create_ksus": {
                "workflow_function": self.create_ksus,
                "clean_function": self.clean_items_ksu_create,
            },
            "update_ksus": {
                "workflow_function": self.update_ksus,
                "clean_function": self.clean_items_ksu_update,
            },
            "delete_ksus": {
                "workflow_function": self.delete_ksus,
            },
            "clone_ksu": {
                "workflow_function": self.clone_ksu,
            },
            "move_ksu": {
                "workflow_function": self.move_ksu,
            },
            "create_cloud_credentials": {
                "workflow_function": self.create_cloud_credentials,
                "clean_function": self.clean_items_cloud_credentials_create,
            },
            "update_cloud_credentials": {
                "workflow_function": self.update_cloud_credentials,
                "clean_function": self.clean_items_cloud_credentials_update,
            },
            "delete_cloud_credentials": {
                "workflow_function": self.delete_cloud_credentials,
            },
            "dummy_operation": {
                "workflow_function": self.dummy_operation,
            },
        }

        super().__init__(msg, self.logger)

    @property
    def kubeconfig(self):
        return self._kubeconfig

    # Imported methods
    from osm_lcm.odu_libs.vim_mgmt import (
        create_cloud_credentials,
        update_cloud_credentials,
        delete_cloud_credentials,
        clean_items_cloud_credentials_create,
        clean_items_cloud_credentials_update,
    )
    from osm_lcm.odu_libs.cluster_mgmt import (
        create_cluster,
        update_cluster,
        delete_cluster,
        register_cluster,
        deregister_cluster,
        clean_items_cluster_create,
        clean_items_cluster_update,
        clean_items_cluster_register,
        clean_items_cluster_deregister,
        get_cluster_credentials,
    )
    from osm_lcm.odu_libs.ksu import (
        create_ksus,
        update_ksus,
        delete_ksus,
        clone_ksu,
        move_ksu,
        clean_items_ksu_create,
        clean_items_ksu_update,
        clean_items_ksu_delete,
    )
    from osm_lcm.odu_libs.oka import (
        create_oka,
        update_oka,
        delete_oka,
        clean_items_oka_create,
        clean_items_oka_update,
        clean_items_oka_delete,
    )
    from osm_lcm.odu_libs.profiles import (
        create_profile,
        delete_profile,
        attach_profile_to_cluster,
        detach_profile_from_cluster,
    )
    from osm_lcm.odu_libs.workflows import (
        check_workflow_status,
        readiness_loop,
    )
    from osm_lcm.odu_libs.render import (
        render_jinja_template,
        render_yaml_template,
    )
    from osm_lcm.odu_libs.common import (
        create_secret,
        delete_secret,
    )

    async def launch_workflow(self, key, op_id, op_params, content):
        self.logger.info(
            f"Workflow is getting into launch. Key: {key}. Operation: {op_id}. Params: {op_params}. Content: {content}"
        )
        workflow_function = self._workflows[key]["workflow_function"]
        self.logger.info("workflow function : {}".format(workflow_function))
        try:
            result, workflow_name = await workflow_function(op_id, op_params, content)
            return result, workflow_name
        except Exception as e:
            self.logger.error(f"Error launching workflow: {e}")
            return False, str(e)

    async def dummy_clean_items(self, op_id, op_params, content):
        self.logger.info(
            f"dummy_clean_items Enter. Operation {op_id}. Params: {op_params}"
        )
        self.logger.debug(f"Content: {content}")
        return True, "OK"

    async def clean_items_workflow(self, key, op_id, op_params, content):
        self.logger.info(
            f"Cleaning items created during workflow launch. Key: {key}. Operation: {op_id}. Params: {op_params}. Content: {content}"
        )
        clean_items_function = self._workflows[key].get(
            "clean_function", self.dummy_clean_items
        )
        self.logger.info("clean items function : {}".format(clean_items_function))
        return await clean_items_function(op_id, op_params, content)

    async def dummy_operation(self, op_id, op_params, content):
        self.logger.info("Empty operation status Enter")
        self.logger.info(f"Operation {op_id}. Params: {op_params}. Content: {content}")
        return content["workflow_name"]

    async def clean_items(self, items):
        # Delete pods
        for pod in items.get("pods", []):
            name = pod["name"]
            namespace = pod["namespace"]
            self.logger.info(f"Deleting pod {name} in namespace {namespace}")
            self.logger.debug(f"Testing kubectl: {self._kubectl}")
            self.logger.debug(
                f"Testing kubectl configuration: {self._kubectl.configuration}"
            )
            self.logger.debug(
                f"Testing kubectl configuration Host: {self._kubectl.configuration.host}"
            )
            await self._kubectl.delete_pod(name, namespace)
        # Delete secrets
        for secret in items.get("secrets", []):
            name = secret["name"]
            namespace = secret["namespace"]
            self.logger.info(f"Deleting secret {name} in namespace {namespace}")
            self.logger.debug(f"Testing kubectl: {self._kubectl}")
            self.logger.debug(
                f"Testing kubectl configuration: {self._kubectl.configuration}"
            )
            self.logger.debug(
                f"Testing kubectl configuration Host: {self._kubectl.configuration.host}"
            )
            self.delete_secret(name, namespace)
        # Delete pvcs
        for pvc in items.get("pvcs", []):
            name = pvc["name"]
            namespace = pvc["namespace"]
            self.logger.info(f"Deleting pvc {name} in namespace {namespace}")
            self.logger.debug(f"Testing kubectl: {self._kubectl}")
            self.logger.debug(
                f"Testing kubectl configuration: {self._kubectl.configuration}"
            )
            self.logger.debug(
                f"Testing kubectl configuration Host: {self._kubectl.configuration.host}"
            )
            await self._kubectl.delete_pvc(name, namespace)
