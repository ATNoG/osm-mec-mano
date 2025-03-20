# -*- coding: utf-8 -*-

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

__author__ = (
    "Shrinithi R <shrinithi.r@tataelxsi.co.in>",
    "Shahithya Y <shahithya.y@tataelxsi.co.in>",
)

import copy
import logging
from time import time
import traceback
from osm_lcm.lcm_utils import LcmBase
from copy import deepcopy
from osm_lcm import odu_workflows
from osm_lcm import vim_sdn
from osm_lcm.data_utils.list_utils import find_in_list
from osm_lcm.n2vc.kubectl import Kubectl
import yaml

MAP_PROFILE = {
    "infra_controller_profiles": "infra-controllers",
    "infra_config_profiles": "infra-configs",
    "resource_profiles": "managed_resources",
    "app_profiles": "apps",
}


class GitOpsLcm(LcmBase):
    db_collection = "gitops"
    workflow_status = None
    resource_status = None

    profile_collection_mapping = {
        "infra_controller_profiles": "k8sinfra_controller",
        "infra_config_profiles": "k8sinfra_config",
        "resource_profiles": "k8sresource",
        "app_profiles": "k8sapp",
    }

    profile_type_mapping = {
        "infra-controllers": "infra_controller_profiles",
        "infra-configs": "infra_config_profiles",
        "managed-resources": "resource_profiles",
        "applications": "app_profiles",
    }

    def __init__(self, msg, lcm_tasks, config):
        self.logger = logging.getLogger("lcm.gitops")
        self.lcm_tasks = lcm_tasks
        self.odu = odu_workflows.OduWorkflow(msg, self.lcm_tasks, config)
        self._checkloop_kustomization_timeout = 900
        self._checkloop_resource_timeout = 900
        self._workflows = {}
        super().__init__(msg, self.logger)

    async def check_dummy_operation(self, op_id, op_params, content):
        self.logger.info(f"Operation {op_id}. Params: {op_params}. Content: {content}")
        return True, "OK"

    def initialize_operation(self, item_id, op_id):
        db_item = self.db.get_one(self.db_collection, {"_id": item_id})
        operation = next(
            (op for op in db_item.get("operationHistory", []) if op["op_id"] == op_id),
            None,
        )
        operation["workflowState"] = "PROCESSING"
        operation["resourceState"] = "NOT_READY"
        operation["operationState"] = "IN_PROGRESS"
        operation["gitOperationInfo"] = None
        db_item["current_operation"] = operation["op_id"]
        self.db.set_one(self.db_collection, {"_id": item_id}, db_item)

    def get_operation_params(self, item, operation_id):
        operation_history = item.get("operationHistory", [])
        operation = find_in_list(
            operation_history, lambda op: op["op_id"] == operation_id
        )
        return operation.get("operationParams", {})

    def get_operation_type(self, item, operation_id):
        operation_history = item.get("operationHistory", [])
        operation = find_in_list(
            operation_history, lambda op: op["op_id"] == operation_id
        )
        return operation.get("operationType", {})

    def update_state_operation_history(
        self, content, op_id, workflow_state=None, resource_state=None
    ):
        self.logger.info(
            f"Update state of operation {op_id} in Operation History in DB"
        )
        self.logger.info(
            f"Workflow state: {workflow_state}. Resource state: {resource_state}"
        )
        self.logger.debug(f"Content: {content}")

        op_num = 0
        for operation in content["operationHistory"]:
            self.logger.debug("Operations: {}".format(operation))
            if operation["op_id"] == op_id:
                self.logger.debug("Found operation number: {}".format(op_num))
                if workflow_state is not None:
                    operation["workflowState"] = workflow_state

                if resource_state is not None:
                    operation["resourceState"] = resource_state
                break
            op_num += 1
        self.logger.debug("content: {}".format(content))

        return content

    def update_operation_history(
        self, content, op_id, workflow_status=None, resource_status=None, op_end=True
    ):
        self.logger.info(
            f"Update Operation History in DB. Workflow status: {workflow_status}. Resource status: {resource_status}"
        )
        self.logger.debug(f"Content: {content}")

        op_num = 0
        for operation in content["operationHistory"]:
            self.logger.debug("Operations: {}".format(operation))
            if operation["op_id"] == op_id:
                self.logger.debug("Found operation number: {}".format(op_num))
                if workflow_status is not None:
                    if workflow_status:
                        operation["workflowState"] = "COMPLETED"
                        operation["result"] = True
                    else:
                        operation["workflowState"] = "ERROR"
                        operation["operationState"] = "FAILED"
                        operation["result"] = False

                if resource_status is not None:
                    if resource_status:
                        operation["resourceState"] = "READY"
                        operation["operationState"] = "COMPLETED"
                        operation["result"] = True
                    else:
                        operation["resourceState"] = "NOT_READY"
                        operation["operationState"] = "FAILED"
                        operation["result"] = False

                if op_end:
                    now = time()
                    operation["endDate"] = now
                break
            op_num += 1
        self.logger.debug("content: {}".format(content))

        return content

    async def check_workflow_and_update_db(self, op_id, workflow_name, db_content):
        workflow_status, workflow_msg = await self.odu.check_workflow_status(
            op_id, workflow_name
        )
        self.logger.info(
            "Workflow Status: {} Workflow Message: {}".format(
                workflow_status, workflow_msg
            )
        )
        operation_type = self.get_operation_type(db_content, op_id)
        if operation_type == "create" and workflow_status:
            db_content["state"] = "CREATED"
        elif operation_type == "create" and not workflow_status:
            db_content["state"] = "FAILED_CREATION"
        elif operation_type == "delete" and workflow_status:
            db_content["state"] = "DELETED"
        elif operation_type == "delete" and not workflow_status:
            db_content["state"] = "FAILED_DELETION"

        if workflow_status:
            db_content["resourceState"] = "IN_PROGRESS.GIT_SYNCED"
        else:
            db_content["resourceState"] = "ERROR"

        db_content = self.update_operation_history(
            db_content, op_id, workflow_status, None
        )
        self.db.set_one(self.db_collection, {"_id": db_content["_id"]}, db_content)
        return workflow_status

    async def check_resource_and_update_db(
        self, resource_name, op_id, op_params, db_content
    ):
        workflow_status = True

        resource_status, resource_msg = await self.check_resource_status(
            resource_name, op_id, op_params, db_content
        )
        self.logger.info(
            "Resource Status: {} Resource Message: {}".format(
                resource_status, resource_msg
            )
        )

        if resource_status:
            db_content["resourceState"] = "READY"
        else:
            db_content["resourceState"] = "ERROR"

        db_content = self.update_operation_history(
            db_content, op_id, workflow_status, resource_status
        )
        db_content["operatingState"] = "IDLE"
        db_content["current_operation"] = None
        return resource_status, db_content

    async def common_check_list(
        self, op_id, checkings_list, db_collection, db_item, kubectl_obj=None
    ):
        try:
            for checking in checkings_list:
                if checking["enable"]:
                    status, message = await self.odu.readiness_loop(
                        op_id=op_id,
                        item=checking["item"],
                        name=checking["name"],
                        namespace=checking["namespace"],
                        condition=checking.get("condition"),
                        deleted=checking.get("deleted", False),
                        timeout=checking["timeout"],
                        kubectl_obj=kubectl_obj,
                    )
                    if not status:
                        error_message = "Resources not ready: "
                        error_message += checking.get("error_message", "")
                        return status, f"{error_message}: {message}"
                    else:
                        db_item["resourceState"] = checking["resourceState"]
                        db_item = self.update_state_operation_history(
                            db_item, op_id, None, checking["resourceState"]
                        )
                        self.db.set_one(db_collection, {"_id": db_item["_id"]}, db_item)
        except Exception as e:
            self.logger.debug(traceback.format_exc())
            self.logger.debug(f"Exception: {e}", exc_info=True)
            return False, f"Unexpected exception: {e}"
        return True, "OK"

    async def check_resource_status(self, key, op_id, op_params, content):
        self.logger.info(
            f"Check resource status. Key: {key}. Operation: {op_id}. Params: {op_params}."
        )
        self.logger.debug(f"Check resource status. Content: {content}")
        check_resource_function = self._workflows.get(key, {}).get(
            "check_resource_function"
        )
        self.logger.info("check_resource function : {}".format(check_resource_function))
        if check_resource_function:
            return await check_resource_function(op_id, op_params, content)
        else:
            return await self.check_dummy_operation(op_id, op_params, content)

    def check_force_delete_and_delete_from_db(
        self, _id, workflow_status, resource_status, force
    ):
        self.logger.info(
            f" Force: {force} Workflow status: {workflow_status} Resource Status: {resource_status}"
        )
        if force and (not workflow_status or not resource_status):
            self.db.del_one(self.db_collection, {"_id": _id})
            return True
        return False

    def decrypt_age_keys(self, content, fields=["age_pubkey", "age_privkey"]):
        self.db.encrypt_decrypt_fields(
            content,
            "decrypt",
            fields,
            schema_version="1.11",
            salt=content["_id"],
        )

    def encrypt_age_keys(self, content, fields=["age_pubkey", "age_privkey"]):
        self.db.encrypt_decrypt_fields(
            content,
            "encrypt",
            fields,
            schema_version="1.11",
            salt=content["_id"],
        )

    def decrypted_copy(self, content, fields=["age_pubkey", "age_privkey"]):
        # This deep copy is intended to be passed to ODU workflows.
        content_copy = copy.deepcopy(content)

        # decrypting the key
        self.db.encrypt_decrypt_fields(
            content_copy,
            "decrypt",
            fields,
            schema_version="1.11",
            salt=content_copy["_id"],
        )
        return content_copy

    def delete_profile_ksu(self, _id, profile_type):
        filter_q = {"profile": {"_id": _id, "profile_type": profile_type}}
        ksu_list = self.db.get_list("ksus", filter_q)
        if ksu_list:
            self.db.del_list("ksus", filter_q)
        return

    def cluster_kubectl(self, db_cluster):
        cluster_kubeconfig = db_cluster["credentials"]
        kubeconfig_path = f"/tmp/{db_cluster['_id']}_kubeconfig.yaml"
        with open(kubeconfig_path, "w") as kubeconfig_file:
            yaml.safe_dump(cluster_kubeconfig, kubeconfig_file)
        return Kubectl(config_file=kubeconfig_path)


class ClusterLcm(GitOpsLcm):
    db_collection = "clusters"

    def __init__(self, msg, lcm_tasks, config):
        """
        Init, Connect to database, filesystem storage, and messaging
        :param config: two level dictionary with configuration. Top level should contain 'database', 'storage',
        :return: None
        """
        super().__init__(msg, lcm_tasks, config)
        self._workflows = {
            "create_cluster": {
                "check_resource_function": self.check_create_cluster,
            },
            "register_cluster": {
                "check_resource_function": self.check_register_cluster,
            },
            "update_cluster": {
                "check_resource_function": self.check_update_cluster,
            },
            "delete_cluster": {
                "check_resource_function": self.check_delete_cluster,
            },
        }
        self.regist = vim_sdn.K8sClusterLcm(msg, self.lcm_tasks, config)

    async def create(self, params, order_id):
        self.logger.info("cluster Create Enter")

        # To get the cluster and op ids
        cluster_id = params["cluster_id"]
        op_id = params["operation_id"]

        # To initialize the operation states
        self.initialize_operation(cluster_id, op_id)

        # To get the cluster
        db_cluster = self.db.get_one("clusters", {"_id": cluster_id})

        # To get the operation params details
        op_params = self.get_operation_params(db_cluster, op_id)

        # To copy the cluster content and decrypting fields to use in workflows
        db_cluster_copy = self.decrypted_copy(db_cluster)
        workflow_content = {
            "cluster": db_cluster_copy,
        }

        # To get the vim account details
        db_vim = self.db.get_one("vim_accounts", {"name": db_cluster["vim_account"]})
        workflow_content["vim_account"] = db_vim

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "create_cluster", op_id, op_params, workflow_content
        )
        if not workflow_res:
            self.logger.error(f"Failed to launch workflow: {workflow_name}")
            db_cluster["state"] = "FAILED_CREATION"
            db_cluster["resourceState"] = "ERROR"
            db_cluster = self.update_operation_history(
                db_cluster, op_id, workflow_status=False, resource_status=None
            )
            self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)
            # Clean items used in the workflow, no matter if the workflow succeeded
            clean_status, clean_msg = await self.odu.clean_items_workflow(
                "create_cluster", op_id, op_params, workflow_content
            )
            self.logger.info(
                f"clean_status is :{clean_status} and clean_msg is :{clean_msg}"
            )
            return

        self.logger.info("workflow_name is: {}".format(workflow_name))
        workflow_status, workflow_msg = await self.odu.check_workflow_status(
            op_id, workflow_name
        )
        self.logger.info(
            "workflow_status is: {} and workflow_msg is: {}".format(
                workflow_status, workflow_msg
            )
        )
        if workflow_status:
            db_cluster["state"] = "CREATED"
            db_cluster["resourceState"] = "IN_PROGRESS.GIT_SYNCED"
        else:
            db_cluster["state"] = "FAILED_CREATION"
            db_cluster["resourceState"] = "ERROR"
        # has to call update_operation_history return content
        db_cluster = self.update_operation_history(
            db_cluster, op_id, workflow_status, None
        )
        self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)

        # Clean items used in the workflow, no matter if the workflow succeeded
        clean_status, clean_msg = await self.odu.clean_items_workflow(
            "create_cluster", op_id, op_params, workflow_content
        )
        self.logger.info(
            f"clean_status is :{clean_status} and clean_msg is :{clean_msg}"
        )

        if workflow_status:
            resource_status, resource_msg = await self.check_resource_status(
                "create_cluster", op_id, op_params, workflow_content
            )
            self.logger.info(
                "resource_status is :{} and resource_msg is :{}".format(
                    resource_status, resource_msg
                )
            )
            if resource_status:
                db_cluster["resourceState"] = "READY"
            else:
                db_cluster["resourceState"] = "ERROR"

        db_cluster["operatingState"] = "IDLE"
        db_cluster = self.update_operation_history(
            db_cluster, op_id, workflow_status, resource_status
        )
        db_cluster["current_operation"] = None

        # Retrieve credentials
        cluster_creds = None
        if db_cluster["resourceState"] == "READY" and db_cluster["state"] == "CREATED":
            result, cluster_creds = await self.odu.get_cluster_credentials(db_cluster)
            # TODO: manage the case where the credentials are not available
            if result:
                db_cluster["credentials"] = cluster_creds

        # Update db_cluster
        self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)
        self.update_default_profile_agekeys(db_cluster_copy)
        self.update_profile_state(db_cluster, workflow_status, resource_status)

        # Register the cluster in k8sclusters collection
        db_register = self.db.get_one("k8sclusters", {"name": db_cluster["name"]})
        if cluster_creds:
            db_register["credentials"] = cluster_creds
            # To call the lcm.py for registering the cluster in k8scluster lcm.
            self.db.set_one("k8sclusters", {"_id": db_register["_id"]}, db_register)
            register = await self.regist.create(db_register, order_id)
            self.logger.debug(f"Register is : {register}")
        else:
            db_register["_admin"]["operationalState"] = "ERROR"
            result, cluster_creds = await self.odu.get_cluster_credentials(db_cluster)
            # To call the lcm.py for registering the cluster in k8scluster lcm.
            db_register["credentials"] = cluster_creds
            self.db.set_one("k8sclusters", {"_id": db_register["_id"]}, db_register)

        return

    async def check_create_cluster(self, op_id, op_params, content):
        self.logger.info(
            f"check_create_cluster Operation {op_id}. Params: {op_params}."
        )
        db_cluster = content["cluster"]
        cluster_name = db_cluster["git_name"].lower()
        cluster_kustomization_name = cluster_name
        db_vim_account = content["vim_account"]
        cloud_type = db_vim_account["vim_type"]
        nodepool_name = ""
        if cloud_type == "aws":
            nodepool_name = f"{cluster_name}-nodegroup"
            cluster_name = f"{cluster_name}-cluster"
        elif cloud_type == "gcp":
            nodepool_name = f"nodepool-{cluster_name}"
        bootstrap = op_params.get("bootstrap", True)
        if cloud_type in ("azure", "gcp", "aws"):
            checkings_list = [
                {
                    "item": "kustomization",
                    "name": cluster_kustomization_name,
                    "namespace": "managed-resources",
                    "condition": {
                        "jsonpath_filter": "status.conditions[?(@.type=='Ready')].status",
                        "value": "True",
                    },
                    "timeout": 1500,
                    "enable": True,
                    "resourceState": "IN_PROGRESS.KUSTOMIZATION_READY",
                },
                {
                    "item": f"cluster_{cloud_type}",
                    "name": cluster_name,
                    "namespace": "",
                    "condition": {
                        "jsonpath_filter": "status.conditions[?(@.type=='Synced')].status",
                        "value": "True",
                    },
                    "timeout": self._checkloop_resource_timeout,
                    "enable": True,
                    "resourceState": "IN_PROGRESS.RESOURCE_SYNCED.CLUSTER",
                },
                {
                    "item": f"cluster_{cloud_type}",
                    "name": cluster_name,
                    "namespace": "",
                    "condition": {
                        "jsonpath_filter": "status.conditions[?(@.type=='Ready')].status",
                        "value": "True",
                    },
                    "timeout": self._checkloop_resource_timeout,
                    "enable": True,
                    "resourceState": "IN_PROGRESS.RESOURCE_READY.CLUSTER",
                },
                {
                    "item": "kustomization",
                    "name": f"{cluster_kustomization_name}-bstrp-fluxctrl",
                    "namespace": "managed-resources",
                    "condition": {
                        "jsonpath_filter": "status.conditions[?(@.type=='Ready')].status",
                        "value": "True",
                    },
                    "timeout": self._checkloop_resource_timeout,
                    "enable": bootstrap,
                    "resourceState": "IN_PROGRESS.BOOTSTRAP_OK",
                },
            ]
        else:
            return False, "Not suitable VIM account to check cluster status"
        if nodepool_name:
            nodepool_check = {
                "item": f"nodepool_{cloud_type}",
                "name": nodepool_name,
                "namespace": "",
                "condition": {
                    "jsonpath_filter": "status.conditions[?(@.type=='Ready')].status",
                    "value": "True",
                },
                "timeout": self._checkloop_resource_timeout,
                "enable": True,
                "resourceState": "IN_PROGRESS.RESOURCE_READY.NODEPOOL",
            }
            checkings_list.insert(3, nodepool_check)
        return await self.common_check_list(
            op_id, checkings_list, "clusters", db_cluster
        )

    def update_default_profile_agekeys(self, db_cluster):
        profiles = [
            "infra_controller_profiles",
            "infra_config_profiles",
            "app_profiles",
            "resource_profiles",
        ]
        self.logger.debug("the db_cluster is :{}".format(db_cluster))
        for profile_type in profiles:
            profile_id = db_cluster[profile_type]
            db_collection = self.profile_collection_mapping[profile_type]
            db_profile = self.db.get_one(db_collection, {"_id": profile_id})
            db_profile["age_pubkey"] = db_cluster["age_pubkey"]
            db_profile["age_privkey"] = db_cluster["age_privkey"]
            self.encrypt_age_keys(db_profile)
            self.db.set_one(db_collection, {"_id": db_profile["_id"]}, db_profile)

    def update_profile_state(self, db_cluster, workflow_status, resource_status):
        profiles = [
            "infra_controller_profiles",
            "infra_config_profiles",
            "app_profiles",
            "resource_profiles",
        ]
        self.logger.debug("the db_cluster is :{}".format(db_cluster))
        for profile_type in profiles:
            profile_id = db_cluster[profile_type]
            db_collection = self.profile_collection_mapping[profile_type]
            db_profile = self.db.get_one(db_collection, {"_id": profile_id})
            op_id = db_profile["operationHistory"][-1].get("op_id")
            db_profile["state"] = db_cluster["state"]
            db_profile["resourceState"] = db_cluster["resourceState"]
            db_profile["operatingState"] = db_cluster["operatingState"]
            db_profile = self.update_operation_history(
                db_profile, op_id, workflow_status, resource_status
            )
            self.db.set_one(db_collection, {"_id": db_profile["_id"]}, db_profile)

    async def delete(self, params, order_id):
        self.logger.info("cluster delete Enter")

        try:
            # To get the cluster and op ids
            cluster_id = params["cluster_id"]
            op_id = params["operation_id"]

            # To initialize the operation states
            self.initialize_operation(cluster_id, op_id)

            # To get the cluster
            db_cluster = self.db.get_one("clusters", {"_id": cluster_id})

            # To get the operation params details
            op_params = self.get_operation_params(db_cluster, op_id)

            # To copy the cluster content and decrypting fields to use in workflows
            workflow_content = {
                "cluster": self.decrypted_copy(db_cluster),
            }

            # To get the vim account details
            db_vim = self.db.get_one(
                "vim_accounts", {"name": db_cluster["vim_account"]}
            )
            workflow_content["vim_account"] = db_vim
        except Exception as e:
            self.logger.debug(traceback.format_exc())
            self.logger.debug(f"Exception: {e}", exc_info=True)
            raise e

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "delete_cluster", op_id, op_params, workflow_content
        )
        if not workflow_res:
            self.logger.error(f"Failed to launch workflow: {workflow_name}")
            db_cluster["state"] = "FAILED_DELETION"
            db_cluster["resourceState"] = "ERROR"
            db_cluster = self.update_operation_history(
                db_cluster, op_id, workflow_status=False, resource_status=None
            )
            self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)
            # Clean items used in the workflow, no matter if the workflow succeeded
            clean_status, clean_msg = await self.odu.clean_items_workflow(
                "delete_cluster", op_id, op_params, workflow_content
            )
            self.logger.info(
                f"clean_status is :{clean_status} and clean_msg is :{clean_msg}"
            )
            return

        self.logger.info("workflow_name is: {}".format(workflow_name))
        workflow_status, workflow_msg = await self.odu.check_workflow_status(
            op_id, workflow_name
        )
        self.logger.info(
            "workflow_status is: {} and workflow_msg is: {}".format(
                workflow_status, workflow_msg
            )
        )
        if workflow_status:
            db_cluster["state"] = "DELETED"
            db_cluster["resourceState"] = "IN_PROGRESS.GIT_SYNCED"
        else:
            db_cluster["state"] = "FAILED_DELETION"
            db_cluster["resourceState"] = "ERROR"
        # has to call update_operation_history return content
        db_cluster = self.update_operation_history(
            db_cluster, op_id, workflow_status, None
        )
        self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)

        # Clean items used in the workflow or in the cluster, no matter if the workflow succeeded
        clean_status, clean_msg = await self.odu.clean_items_workflow(
            "delete_cluster", op_id, op_params, workflow_content
        )
        self.logger.info(
            f"clean_status is :{clean_status} and clean_msg is :{clean_msg}"
        )

        if workflow_status:
            resource_status, resource_msg = await self.check_resource_status(
                "delete_cluster", op_id, op_params, workflow_content
            )
            self.logger.info(
                "resource_status is :{} and resource_msg is :{}".format(
                    resource_status, resource_msg
                )
            )
            if resource_status:
                db_cluster["resourceState"] = "READY"
            else:
                db_cluster["resourceState"] = "ERROR"

        db_cluster["operatingState"] = "IDLE"
        db_cluster = self.update_operation_history(
            db_cluster, op_id, workflow_status, resource_status
        )
        db_cluster["current_operation"] = None
        self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)

        force = params.get("force", False)
        if force:
            force_delete_status = self.check_force_delete_and_delete_from_db(
                cluster_id, workflow_status, resource_status, force
            )
            if force_delete_status:
                return

        # To delete it from DB
        if db_cluster["state"] == "DELETED":
            self.delete_cluster(db_cluster)

        # To delete it from k8scluster collection
        self.db.del_one("k8sclusters", {"name": db_cluster["name"]})

        return

    async def check_delete_cluster(self, op_id, op_params, content):
        self.logger.info(
            f"check_delete_cluster Operation {op_id}. Params: {op_params}."
        )
        self.logger.debug(f"Content: {content}")
        db_cluster = content["cluster"]
        cluster_name = db_cluster["git_name"].lower()
        cluster_kustomization_name = cluster_name
        db_vim_account = content["vim_account"]
        cloud_type = db_vim_account["vim_type"]
        if cloud_type == "aws":
            cluster_name = f"{cluster_name}-cluster"
        if cloud_type in ("azure", "gcp", "aws"):
            checkings_list = [
                {
                    "item": "kustomization",
                    "name": cluster_kustomization_name,
                    "namespace": "managed-resources",
                    "deleted": True,
                    "timeout": self._checkloop_kustomization_timeout,
                    "enable": True,
                    "resourceState": "IN_PROGRESS.KUSTOMIZATION_DELETED",
                },
                {
                    "item": f"cluster_{cloud_type}",
                    "name": cluster_name,
                    "namespace": "",
                    "deleted": True,
                    "timeout": self._checkloop_resource_timeout,
                    "enable": True,
                    "resourceState": "IN_PROGRESS.RESOURCE_DELETED.CLUSTER",
                },
            ]
        else:
            return False, "Not suitable VIM account to check cluster status"
        return await self.common_check_list(
            op_id, checkings_list, "clusters", db_cluster
        )

    def delete_cluster(self, db_cluster):
        # Actually, item_content is equal to db_cluster
        # detach profiles
        update_dict = None
        profiles_to_detach = [
            "infra_controller_profiles",
            "infra_config_profiles",
            "app_profiles",
            "resource_profiles",
        ]
        """
        profiles_collection = {
            "infra_controller_profiles": "k8sinfra_controller",
            "infra_config_profiles": "k8sinfra_config",
            "app_profiles": "k8sapp",
            "resource_profiles": "k8sresource",
        }
        """
        for profile_type in profiles_to_detach:
            if db_cluster.get(profile_type):
                profile_ids = db_cluster[profile_type]
                profile_ids_copy = deepcopy(profile_ids)
                for profile_id in profile_ids_copy:
                    db_collection = self.profile_collection_mapping[profile_type]
                    db_profile = self.db.get_one(db_collection, {"_id": profile_id})
                    self.logger.debug("the db_profile is :{}".format(db_profile))
                    self.logger.debug(
                        "the item_content name is :{}".format(db_cluster["name"])
                    )
                    self.logger.debug(
                        "the db_profile name is :{}".format(db_profile["name"])
                    )
                    if db_cluster["name"] == db_profile["name"]:
                        self.delete_profile_ksu(profile_id, profile_type)
                        self.db.del_one(db_collection, {"_id": profile_id})
                    else:
                        profile_ids.remove(profile_id)
                        update_dict = {profile_type: profile_ids}
                        self.db.set_one(
                            "clusters", {"_id": db_cluster["_id"]}, update_dict
                        )
        self.db.del_one("clusters", {"_id": db_cluster["_id"]})

    async def attach_profile(self, params, order_id):
        self.logger.info("profile attach Enter")

        # To get the cluster and op ids
        cluster_id = params["cluster_id"]
        op_id = params["operation_id"]

        # To initialize the operation states
        self.initialize_operation(cluster_id, op_id)

        # To get the cluster
        db_cluster = self.db.get_one("clusters", {"_id": cluster_id})

        # To get the operation params details
        op_params = self.get_operation_params(db_cluster, op_id)

        # To copy the cluster content and decrypting fields to use in workflows
        workflow_content = {
            "cluster": self.decrypted_copy(db_cluster),
        }

        # To get the profile details
        profile_id = params["profile_id"]
        profile_type = params["profile_type"]
        profile_collection = self.profile_collection_mapping[profile_type]
        db_profile = self.db.get_one(profile_collection, {"_id": profile_id})
        db_profile["profile_type"] = profile_type
        # content["profile"] = db_profile
        workflow_content["profile"] = db_profile

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "attach_profile_to_cluster", op_id, op_params, workflow_content
        )
        if not workflow_res:
            self.logger.error(f"Failed to launch workflow: {workflow_name}")
            db_cluster["resourceState"] = "ERROR"
            self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)
            db_cluster = self.update_operation_history(
                db_cluster, op_id, workflow_status=False, resource_status=None
            )
            return

        self.logger.info("workflow_name is: {}".format(workflow_name))
        workflow_status, workflow_msg = await self.odu.check_workflow_status(
            op_id, workflow_name
        )
        self.logger.info(
            "workflow_status is: {} and workflow_msg is: {}".format(
                workflow_status, workflow_msg
            )
        )
        if workflow_status:
            db_cluster["resourceState"] = "IN_PROGRESS.GIT_SYNCED"
        else:
            db_cluster["resourceState"] = "ERROR"
        # has to call update_operation_history return content
        db_cluster = self.update_operation_history(
            db_cluster, op_id, workflow_status, None
        )
        self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)

        if workflow_status:
            resource_status, resource_msg = await self.check_resource_status(
                "attach_profile_to_cluster", op_id, op_params, workflow_content
            )
            self.logger.info(
                "resource_status is :{} and resource_msg is :{}".format(
                    resource_status, resource_msg
                )
            )
            if resource_status:
                db_cluster["resourceState"] = "READY"
            else:
                db_cluster["resourceState"] = "ERROR"

        db_cluster["operatingState"] = "IDLE"
        db_cluster = self.update_operation_history(
            db_cluster, op_id, workflow_status, resource_status
        )
        profile_list = db_cluster[profile_type]
        if resource_status:
            profile_list.append(profile_id)
            db_cluster[profile_type] = profile_list
        db_cluster["current_operation"] = None
        self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)

        return

    async def detach_profile(self, params, order_id):
        self.logger.info("profile dettach Enter")

        # To get the cluster and op ids
        cluster_id = params["cluster_id"]
        op_id = params["operation_id"]

        # To initialize the operation states
        self.initialize_operation(cluster_id, op_id)

        # To get the cluster
        db_cluster = self.db.get_one("clusters", {"_id": cluster_id})

        # To get the operation params details
        op_params = self.get_operation_params(db_cluster, op_id)

        # To copy the cluster content and decrypting fields to use in workflows
        workflow_content = {
            "cluster": self.decrypted_copy(db_cluster),
        }

        # To get the profile details
        profile_id = params["profile_id"]
        profile_type = params["profile_type"]
        profile_collection = self.profile_collection_mapping[profile_type]
        db_profile = self.db.get_one(profile_collection, {"_id": profile_id})
        db_profile["profile_type"] = profile_type
        workflow_content["profile"] = db_profile

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "detach_profile_from_cluster", op_id, op_params, workflow_content
        )
        if not workflow_res:
            self.logger.error(f"Failed to launch workflow: {workflow_name}")
            db_cluster["resourceState"] = "ERROR"
            db_cluster = self.update_operation_history(
                db_cluster, op_id, workflow_status=False, resource_status=None
            )
            self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)
            return

        self.logger.info("workflow_name is: {}".format(workflow_name))
        workflow_status, workflow_msg = await self.odu.check_workflow_status(
            op_id, workflow_name
        )
        self.logger.info(
            "workflow_status is: {} and workflow_msg is: {}".format(
                workflow_status, workflow_msg
            )
        )
        if workflow_status:
            db_cluster["resourceState"] = "IN_PROGRESS.GIT_SYNCED"
        else:
            db_cluster["resourceState"] = "ERROR"
        # has to call update_operation_history return content
        db_cluster = self.update_operation_history(
            db_cluster, op_id, workflow_status, None
        )
        self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)

        if workflow_status:
            resource_status, resource_msg = await self.check_resource_status(
                "detach_profile_from_cluster", op_id, op_params, workflow_content
            )
            self.logger.info(
                "resource_status is :{} and resource_msg is :{}".format(
                    resource_status, resource_msg
                )
            )
            if resource_status:
                db_cluster["resourceState"] = "READY"
            else:
                db_cluster["resourceState"] = "ERROR"

        db_cluster["operatingState"] = "IDLE"
        db_cluster = self.update_operation_history(
            db_cluster, op_id, workflow_status, resource_status
        )
        profile_list = db_cluster[profile_type]
        self.logger.info("profile list is : {}".format(profile_list))
        if resource_status:
            profile_list.remove(profile_id)
            db_cluster[profile_type] = profile_list
        db_cluster["current_operation"] = None
        self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)

        return

    async def register(self, params, order_id):
        self.logger.info("cluster register enter")

        # To get the cluster and op ids
        cluster_id = params["cluster_id"]
        op_id = params["operation_id"]

        # To initialize the operation states
        self.initialize_operation(cluster_id, op_id)

        # To get the cluster
        db_cluster = self.db.get_one("clusters", {"_id": cluster_id})

        # To get the operation params details
        op_params = self.get_operation_params(db_cluster, op_id)

        # To copy the cluster content and decrypting fields to use in workflows
        workflow_content = {
            "cluster": self.decrypted_copy(db_cluster),
        }

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "register_cluster", op_id, op_params, workflow_content
        )
        if not workflow_res:
            self.logger.error(f"Failed to launch workflow: {workflow_name}")
            db_cluster["state"] = "FAILED_CREATION"
            db_cluster["resourceState"] = "ERROR"
            db_cluster = self.update_operation_history(
                db_cluster, op_id, workflow_status=False, resource_status=None
            )
            self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)
            # Clean items used in the workflow, no matter if the workflow succeeded
            clean_status, clean_msg = await self.odu.clean_items_workflow(
                "register_cluster", op_id, op_params, workflow_content
            )
            self.logger.info(
                f"clean_status is :{clean_status} and clean_msg is :{clean_msg}"
            )
            return

        self.logger.info("workflow_name is: {}".format(workflow_name))
        workflow_status, workflow_msg = await self.odu.check_workflow_status(
            op_id, workflow_name
        )
        self.logger.info(
            "workflow_status is: {} and workflow_msg is: {}".format(
                workflow_status, workflow_msg
            )
        )
        if workflow_status:
            db_cluster["state"] = "CREATED"
            db_cluster["resourceState"] = "IN_PROGRESS.GIT_SYNCED"
        else:
            db_cluster["state"] = "FAILED_CREATION"
            db_cluster["resourceState"] = "ERROR"
        # has to call update_operation_history return content
        db_cluster = self.update_operation_history(
            db_cluster, op_id, workflow_status, None
        )
        self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)

        # Clean items used in the workflow, no matter if the workflow succeeded
        clean_status, clean_msg = await self.odu.clean_items_workflow(
            "register_cluster", op_id, op_params, workflow_content
        )
        self.logger.info(
            f"clean_status is :{clean_status} and clean_msg is :{clean_msg}"
        )

        if workflow_status:
            resource_status, resource_msg = await self.check_resource_status(
                "register_cluster", op_id, op_params, workflow_content
            )
            self.logger.info(
                "resource_status is :{} and resource_msg is :{}".format(
                    resource_status, resource_msg
                )
            )
            if resource_status:
                db_cluster["resourceState"] = "READY"
            else:
                db_cluster["resourceState"] = "ERROR"

        db_cluster["operatingState"] = "IDLE"
        db_cluster = self.update_operation_history(
            db_cluster, op_id, workflow_status, resource_status
        )
        db_cluster["current_operation"] = None
        self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)

        db_register = self.db.get_one("k8sclusters", {"name": db_cluster["name"]})
        db_register["credentials"] = db_cluster["credentials"]
        self.db.set_one("k8sclusters", {"_id": db_register["_id"]}, db_register)

        if db_cluster["resourceState"] == "READY" and db_cluster["state"] == "CREATED":
            # To call the lcm.py for registering the cluster in k8scluster lcm.
            register = await self.regist.create(db_register, order_id)
            self.logger.debug(f"Register is : {register}")
        else:
            db_register["_admin"]["operationalState"] = "ERROR"
            self.db.set_one("k8sclusters", {"_id": db_register["_id"]}, db_register)

        return

    async def check_register_cluster(self, op_id, op_params, content):
        self.logger.info(
            f"check_register_cluster Operation {op_id}. Params: {op_params}."
        )
        # self.logger.debug(f"Content: {content}")
        db_cluster = content["cluster"]
        cluster_name = db_cluster["git_name"].lower()
        cluster_kustomization_name = cluster_name
        bootstrap = op_params.get("bootstrap", True)
        checkings_list = [
            {
                "item": "kustomization",
                "name": f"{cluster_kustomization_name}-bstrp-fluxctrl",
                "namespace": "managed-resources",
                "condition": {
                    "jsonpath_filter": "status.conditions[?(@.type=='Ready')].status",
                    "value": "True",
                },
                "timeout": self._checkloop_kustomization_timeout,
                "enable": bootstrap,
                "resourceState": "IN_PROGRESS.BOOTSTRAP_OK",
            },
        ]
        return await self.common_check_list(
            op_id, checkings_list, "clusters", db_cluster
        )

    async def deregister(self, params, order_id):
        self.logger.info("cluster deregister enter")

        # To get the cluster and op ids
        cluster_id = params["cluster_id"]
        op_id = params["operation_id"]

        # To initialize the operation states
        self.initialize_operation(cluster_id, op_id)

        # To get the cluster
        db_cluster = self.db.get_one("clusters", {"_id": cluster_id})

        # To get the operation params details
        op_params = self.get_operation_params(db_cluster, op_id)

        # To copy the cluster content and decrypting fields to use in workflows
        workflow_content = {
            "cluster": self.decrypted_copy(db_cluster),
        }

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "deregister_cluster", op_id, op_params, workflow_content
        )
        if not workflow_res:
            self.logger.error(f"Failed to launch workflow: {workflow_name}")
            db_cluster["state"] = "FAILED_DELETION"
            db_cluster["resourceState"] = "ERROR"
            db_cluster = self.update_operation_history(
                db_cluster, op_id, workflow_status=False, resource_status=None
            )
            self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)
            return

        self.logger.info("workflow_name is: {}".format(workflow_name))
        workflow_status, workflow_msg = await self.odu.check_workflow_status(
            op_id, workflow_name
        )
        self.logger.info(
            "workflow_status is: {} and workflow_msg is: {}".format(
                workflow_status, workflow_msg
            )
        )
        if workflow_status:
            db_cluster["resourceState"] = "IN_PROGRESS.GIT_SYNCED"
        else:
            db_cluster["state"] = "FAILED_DELETION"
            db_cluster["resourceState"] = "ERROR"
        # has to call update_operation_history return content
        db_cluster = self.update_operation_history(
            db_cluster, op_id, workflow_status, None
        )
        self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)

        if workflow_status:
            resource_status, resource_msg = await self.check_resource_status(
                "deregister_cluster", op_id, op_params, workflow_content
            )
            self.logger.info(
                "resource_status is :{} and resource_msg is :{}".format(
                    resource_status, resource_msg
                )
            )
            if resource_status:
                db_cluster["resourceState"] = "READY"
            else:
                db_cluster["resourceState"] = "ERROR"

        db_cluster = self.update_operation_history(
            db_cluster, op_id, workflow_status, resource_status
        )
        self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)

        await self.delete(params, order_id)
        # Clean items used in the workflow or in the cluster, no matter if the workflow succeeded
        clean_status, clean_msg = await self.odu.clean_items_workflow(
            "deregister_cluster", op_id, op_params, workflow_content
        )
        self.logger.info(
            f"clean_status is :{clean_status} and clean_msg is :{clean_msg}"
        )
        return

    async def get_creds(self, params, order_id):
        self.logger.info("Cluster get creds Enter")
        cluster_id = params["cluster_id"]
        op_id = params["operation_id"]
        db_cluster = self.db.get_one("clusters", {"_id": cluster_id})
        result, cluster_creds = await self.odu.get_cluster_credentials(db_cluster)
        if result:
            db_cluster["credentials"] = cluster_creds
        op_len = 0
        for operations in db_cluster["operationHistory"]:
            if operations["op_id"] == op_id:
                db_cluster["operationHistory"][op_len]["result"] = result
                db_cluster["operationHistory"][op_len]["endDate"] = time()
            op_len += 1
        db_cluster["current_operation"] = None
        self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)
        self.logger.info("Cluster Get Creds Exit")
        return

    async def update(self, params, order_id):
        self.logger.info("Cluster update Enter")
        # To get the cluster details
        cluster_id = params["cluster_id"]
        db_cluster = self.db.get_one("clusters", {"_id": cluster_id})

        # To get the operation params details
        op_id = params["operation_id"]
        op_params = self.get_operation_params(db_cluster, op_id)

        # To copy the cluster content and decrypting fields to use in workflows
        workflow_content = {
            "cluster": self.decrypted_copy(db_cluster),
        }

        # vim account details
        db_vim = self.db.get_one("vim_accounts", {"name": db_cluster["vim_account"]})
        workflow_content["vim_account"] = db_vim

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "update_cluster", op_id, op_params, workflow_content
        )
        if not workflow_res:
            self.logger.error(f"Failed to launch workflow: {workflow_name}")
            db_cluster["resourceState"] = "ERROR"
            db_cluster = self.update_operation_history(
                db_cluster, op_id, workflow_status=False, resource_status=None
            )
            self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)
            # Clean items used in the workflow, no matter if the workflow succeeded
            clean_status, clean_msg = await self.odu.clean_items_workflow(
                "update_cluster", op_id, op_params, workflow_content
            )
            self.logger.info(
                f"clean_status is :{clean_status} and clean_msg is :{clean_msg}"
            )
            return
        self.logger.info("workflow_name is: {}".format(workflow_name))
        workflow_status, workflow_msg = await self.odu.check_workflow_status(
            op_id, workflow_name
        )
        self.logger.info(
            "Workflow Status: {} Workflow Message: {}".format(
                workflow_status, workflow_msg
            )
        )

        if workflow_status:
            db_cluster["resourceState"] = "IN_PROGRESS.GIT_SYNCED"
        else:
            db_cluster["resourceState"] = "ERROR"

        db_cluster = self.update_operation_history(
            db_cluster, op_id, workflow_status, None
        )
        # self.logger.info("Db content: {}".format(db_content))
        # self.db.set_one(self.db_collection, {"_id": _id}, db_cluster)
        self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)

        # Clean items used in the workflow, no matter if the workflow succeeded
        clean_status, clean_msg = await self.odu.clean_items_workflow(
            "update_cluster", op_id, op_params, workflow_content
        )
        self.logger.info(
            f"clean_status is :{clean_status} and clean_msg is :{clean_msg}"
        )
        if workflow_status:
            resource_status, resource_msg = await self.check_resource_status(
                "update_cluster", op_id, op_params, workflow_content
            )
            self.logger.info(
                "Resource Status: {} Resource Message: {}".format(
                    resource_status, resource_msg
                )
            )

            if resource_status:
                db_cluster["resourceState"] = "READY"
            else:
                db_cluster["resourceState"] = "ERROR"

            db_cluster = self.update_operation_history(
                db_cluster, op_id, workflow_status, resource_status
            )

        db_cluster["operatingState"] = "IDLE"
        # self.logger.info("db_cluster: {}".format(db_cluster))
        # TODO: verify condition
        # For the moment, if the workflow completed successfully, then we update the db accordingly.
        if workflow_status:
            if "k8s_version" in op_params:
                db_cluster["k8s_version"] = op_params["k8s_version"]
            if "node_count" in op_params:
                db_cluster["node_count"] = op_params["node_count"]
            if "node_size" in op_params:
                db_cluster["node_count"] = op_params["node_size"]
            # self.db.set_one(self.db_collection, {"_id": _id}, db_content)
        db_cluster["current_operation"] = None
        self.db.set_one("clusters", {"_id": db_cluster["_id"]}, db_cluster)
        return

    async def check_update_cluster(self, op_id, op_params, content):
        self.logger.info(
            f"check_update_cluster Operation {op_id}. Params: {op_params}."
        )
        self.logger.debug(f"Content: {content}")
        # return await self.check_dummy_operation(op_id, op_params, content)
        db_cluster = content["cluster"]
        cluster_name = db_cluster["git_name"].lower()
        cluster_kustomization_name = cluster_name
        db_vim_account = content["vim_account"]
        cloud_type = db_vim_account["vim_type"]
        if cloud_type == "aws":
            cluster_name = f"{cluster_name}-cluster"
        if cloud_type in ("azure", "gcp", "aws"):
            checkings_list = [
                {
                    "item": "kustomization",
                    "name": cluster_kustomization_name,
                    "namespace": "managed-resources",
                    "condition": {
                        "jsonpath_filter": "status.conditions[?(@.type=='Ready')].status",
                        "value": "True",
                    },
                    "timeout": self._checkloop_kustomization_timeout,
                    "enable": True,
                    "resourceState": "IN_PROGRESS.KUSTOMIZATION_READY",
                },
            ]
        else:
            return False, "Not suitable VIM account to check cluster status"
        # Scale operation
        if "node_count" in op_params:
            checkings_list.append(
                {
                    "item": f"cluster_{cloud_type}",
                    "name": cluster_name,
                    "namespace": "",
                    "condition": {
                        "jsonpath_filter": "status.atProvider.defaultNodePool[0].nodeCount",
                        "value": f"{op_params['node_count']}",
                    },
                    "timeout": self._checkloop_resource_timeout * 3,
                    "enable": True,
                    "resourceState": "IN_PROGRESS.RESOURCE_READY.NODE_COUNT.CLUSTER",
                }
            )
        # Upgrade operation
        if "k8s_version" in op_params:
            checkings_list.append(
                {
                    "item": f"cluster_{cloud_type}",
                    "name": cluster_name,
                    "namespace": "",
                    "condition": {
                        "jsonpath_filter": "status.atProvider.defaultNodePool[0].orchestratorVersion",
                        "value": op_params["k8s_version"],
                    },
                    "timeout": self._checkloop_resource_timeout * 2,
                    "enable": True,
                    "resourceState": "IN_PROGRESS.RESOURCE_READY.K8S_VERSION.CLUSTER",
                }
            )
        return await self.common_check_list(
            op_id, checkings_list, "clusters", db_cluster
        )


class CloudCredentialsLcm(GitOpsLcm):
    db_collection = "vim_accounts"

    def __init__(self, msg, lcm_tasks, config):
        """
        Init, Connect to database, filesystem storage, and messaging
        :param config: two level dictionary with configuration. Top level should contain 'database', 'storage',
        :return: None
        """
        super().__init__(msg, lcm_tasks, config)

    async def add(self, params, order_id):
        self.logger.info("Cloud Credentials create")
        vim_id = params["_id"]
        op_id = vim_id
        op_params = params
        db_content = self.db.get_one(self.db_collection, {"_id": vim_id})
        vim_config = db_content.get("config", {})
        self.db.encrypt_decrypt_fields(
            vim_config.get("credentials"),
            "decrypt",
            ["password", "secret"],
            schema_version=db_content["schema_version"],
            salt=vim_id,
        )

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "create_cloud_credentials", op_id, op_params, db_content
        )

        workflow_status, workflow_msg = await self.odu.check_workflow_status(
            op_id, workflow_name
        )

        self.logger.info(
            "Workflow Status: {} Workflow Msg: {}".format(workflow_status, workflow_msg)
        )

        # Clean items used in the workflow, no matter if the workflow succeeded
        clean_status, clean_msg = await self.odu.clean_items_workflow(
            "create_cloud_credentials", op_id, op_params, db_content
        )
        self.logger.info(
            f"clean_status is :{clean_status} and clean_msg is :{clean_msg}"
        )

        if workflow_status:
            resource_status, resource_msg = await self.check_resource_status(
                "create_cloud_credentials", op_id, op_params, db_content
            )
            self.logger.info(
                "Resource Status: {} Resource Message: {}".format(
                    resource_status, resource_msg
                )
            )

            db_content["_admin"]["operationalState"] = "ENABLED"
            for operation in db_content["_admin"]["operations"]:
                if operation["lcmOperationType"] == "create":
                    operation["operationState"] = "ENABLED"
            self.logger.info("Content : {}".format(db_content))
        self.db.set_one("vim_accounts", {"_id": db_content["_id"]}, db_content)
        return

    async def edit(self, params, order_id):
        self.logger.info("Cloud Credentials Update")
        vim_id = params["_id"]
        op_id = vim_id
        op_params = params
        db_content = self.db.get_one("vim_accounts", {"_id": vim_id})
        vim_config = db_content.get("config", {})
        self.db.encrypt_decrypt_fields(
            vim_config.get("credentials"),
            "decrypt",
            ["password", "secret"],
            schema_version=db_content["schema_version"],
            salt=vim_id,
        )

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "update_cloud_credentials", op_id, op_params, db_content
        )
        workflow_status, workflow_msg = await self.odu.check_workflow_status(
            op_id, workflow_name
        )
        self.logger.info(
            "Workflow Status: {} Workflow Msg: {}".format(workflow_status, workflow_msg)
        )

        # Clean items used in the workflow, no matter if the workflow succeeded
        clean_status, clean_msg = await self.odu.clean_items_workflow(
            "update_cloud_credentials", op_id, op_params, db_content
        )
        self.logger.info(
            f"clean_status is :{clean_status} and clean_msg is :{clean_msg}"
        )

        if workflow_status:
            resource_status, resource_msg = await self.check_resource_status(
                "update_cloud_credentials", op_id, op_params, db_content
            )
            self.logger.info(
                "Resource Status: {} Resource Message: {}".format(
                    resource_status, resource_msg
                )
            )
        return

    async def remove(self, params, order_id):
        self.logger.info("Cloud Credentials remove")
        vim_id = params["_id"]
        op_id = vim_id
        op_params = params
        db_content = self.db.get_one("vim_accounts", {"_id": vim_id})

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "delete_cloud_credentials", op_id, op_params, db_content
        )
        workflow_status, workflow_msg = await self.odu.check_workflow_status(
            op_id, workflow_name
        )
        self.logger.info(
            "Workflow Status: {} Workflow Msg: {}".format(workflow_status, workflow_msg)
        )

        if workflow_status:
            resource_status, resource_msg = await self.check_resource_status(
                "delete_cloud_credentials", op_id, op_params, db_content
            )
            self.logger.info(
                "Resource Status: {} Resource Message: {}".format(
                    resource_status, resource_msg
                )
            )
        self.db.del_one(self.db_collection, {"_id": db_content["_id"]})
        return


class K8sAppLcm(GitOpsLcm):
    db_collection = "k8sapp"

    def __init__(self, msg, lcm_tasks, config):
        """
        Init, Connect to database, filesystem storage, and messaging
        :param config: two level dictionary with configuration. Top level should contain 'database', 'storage',
        :return: None
        """
        super().__init__(msg, lcm_tasks, config)

    async def create(self, params, order_id):
        self.logger.info("App Create Enter")

        op_id = params["operation_id"]
        profile_id = params["profile_id"]

        # To initialize the operation states
        self.initialize_operation(profile_id, op_id)

        content = self.db.get_one("k8sapp", {"_id": profile_id})
        content["profile_type"] = "applications"
        op_params = self.get_operation_params(content, op_id)
        self.db.set_one("k8sapp", {"_id": content["_id"]}, content)

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "create_profile", op_id, op_params, content
        )
        self.logger.info("workflow_name is: {}".format(workflow_name))

        workflow_status = await self.check_workflow_and_update_db(
            op_id, workflow_name, content
        )

        if workflow_status:
            resource_status, content = await self.check_resource_and_update_db(
                "create_profile", op_id, op_params, content
            )
        self.db.set_one(self.db_collection, {"_id": content["_id"]}, content)
        self.logger.info(f"App Create Exit with resource status: {resource_status}")
        return

    async def delete(self, params, order_id):
        self.logger.info("App delete Enter")

        op_id = params["operation_id"]
        profile_id = params["profile_id"]

        # To initialize the operation states
        self.initialize_operation(profile_id, op_id)

        content = self.db.get_one("k8sapp", {"_id": profile_id})
        op_params = self.get_operation_params(content, op_id)

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "delete_profile", op_id, op_params, content
        )
        self.logger.info("workflow_name is: {}".format(workflow_name))

        workflow_status = await self.check_workflow_and_update_db(
            op_id, workflow_name, content
        )

        if workflow_status:
            resource_status, content = await self.check_resource_and_update_db(
                "delete_profile", op_id, op_params, content
            )

        force = params.get("force", False)
        if force:
            force_delete_status = self.check_force_delete_and_delete_from_db(
                profile_id, workflow_status, resource_status, force
            )
            if force_delete_status:
                return

        self.logger.info(f"Resource status: {resource_status}")
        if resource_status:
            content["state"] = "DELETED"
            profile_type = self.profile_type_mapping[content["profile_type"]]
            self.delete_profile_ksu(profile_id, profile_type)
            self.db.set_one(self.db_collection, {"_id": content["_id"]}, content)
            self.db.del_one(self.db_collection, {"_id": content["_id"]})
        self.logger.info(f"App Delete Exit with resource status: {resource_status}")
        return


class K8sResourceLcm(GitOpsLcm):
    db_collection = "k8sresource"

    def __init__(self, msg, lcm_tasks, config):
        """
        Init, Connect to database, filesystem storage, and messaging
        :param config: two level dictionary with configuration. Top level should contain 'database', 'storage',
        :return: None
        """
        super().__init__(msg, lcm_tasks, config)

    async def create(self, params, order_id):
        self.logger.info("Resource Create Enter")

        op_id = params["operation_id"]
        profile_id = params["profile_id"]

        # To initialize the operation states
        self.initialize_operation(profile_id, op_id)

        content = self.db.get_one("k8sresource", {"_id": profile_id})
        content["profile_type"] = "managed-resources"
        op_params = self.get_operation_params(content, op_id)
        self.db.set_one("k8sresource", {"_id": content["_id"]}, content)

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "create_profile", op_id, op_params, content
        )
        self.logger.info("workflow_name is: {}".format(workflow_name))

        workflow_status = await self.check_workflow_and_update_db(
            op_id, workflow_name, content
        )

        if workflow_status:
            resource_status, content = await self.check_resource_and_update_db(
                "create_profile", op_id, op_params, content
            )
        self.db.set_one(self.db_collection, {"_id": content["_id"]}, content)
        self.logger.info(
            f"Resource Create Exit with resource status: {resource_status}"
        )
        return

    async def delete(self, params, order_id):
        self.logger.info("Resource delete Enter")

        op_id = params["operation_id"]
        profile_id = params["profile_id"]

        # To initialize the operation states
        self.initialize_operation(profile_id, op_id)

        content = self.db.get_one("k8sresource", {"_id": profile_id})
        op_params = self.get_operation_params(content, op_id)

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "delete_profile", op_id, op_params, content
        )
        self.logger.info("workflow_name is: {}".format(workflow_name))

        workflow_status = await self.check_workflow_and_update_db(
            op_id, workflow_name, content
        )

        if workflow_status:
            resource_status, content = await self.check_resource_and_update_db(
                "delete_profile", op_id, op_params, content
            )

        force = params.get("force", False)
        if force:
            force_delete_status = self.check_force_delete_and_delete_from_db(
                profile_id, workflow_status, resource_status, force
            )
            if force_delete_status:
                return

        if resource_status:
            content["state"] = "DELETED"
            profile_type = self.profile_type_mapping[content["profile_type"]]
            self.delete_profile_ksu(profile_id, profile_type)
            self.db.set_one(self.db_collection, {"_id": content["_id"]}, content)
            self.db.del_one(self.db_collection, {"_id": content["_id"]})
        self.logger.info(
            f"Resource Delete Exit with resource status: {resource_status}"
        )
        return


class K8sInfraControllerLcm(GitOpsLcm):
    db_collection = "k8sinfra_controller"

    def __init__(self, msg, lcm_tasks, config):
        """
        Init, Connect to database, filesystem storage, and messaging
        :param config: two level dictionary with configuration. Top level should contain 'database', 'storage',
        :return: None
        """
        super().__init__(msg, lcm_tasks, config)

    async def create(self, params, order_id):
        self.logger.info("Infra controller Create Enter")

        op_id = params["operation_id"]
        profile_id = params["profile_id"]

        # To initialize the operation states
        self.initialize_operation(profile_id, op_id)

        content = self.db.get_one("k8sinfra_controller", {"_id": profile_id})
        content["profile_type"] = "infra-controllers"
        op_params = self.get_operation_params(content, op_id)
        self.db.set_one("k8sinfra_controller", {"_id": content["_id"]}, content)

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "create_profile", op_id, op_params, content
        )
        self.logger.info("workflow_name is: {}".format(workflow_name))

        workflow_status = await self.check_workflow_and_update_db(
            op_id, workflow_name, content
        )

        if workflow_status:
            resource_status, content = await self.check_resource_and_update_db(
                "create_profile", op_id, op_params, content
            )
        self.db.set_one(self.db_collection, {"_id": content["_id"]}, content)
        self.logger.info(
            f"Infra Controller Create Exit with resource status: {resource_status}"
        )
        return

    async def delete(self, params, order_id):
        self.logger.info("Infra controller delete Enter")

        op_id = params["operation_id"]
        profile_id = params["profile_id"]

        # To initialize the operation states
        self.initialize_operation(profile_id, op_id)

        content = self.db.get_one("k8sinfra_controller", {"_id": profile_id})
        op_params = self.get_operation_params(content, op_id)

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "delete_profile", op_id, op_params, content
        )
        self.logger.info("workflow_name is: {}".format(workflow_name))

        workflow_status = await self.check_workflow_and_update_db(
            op_id, workflow_name, content
        )

        if workflow_status:
            resource_status, content = await self.check_resource_and_update_db(
                "delete_profile", op_id, op_params, content
            )

        force = params.get("force", False)
        if force:
            force_delete_status = self.check_force_delete_and_delete_from_db(
                profile_id, workflow_status, resource_status, force
            )
            if force_delete_status:
                return

        if resource_status:
            content["state"] = "DELETED"
            profile_type = self.profile_type_mapping[content["profile_type"]]
            self.delete_profile_ksu(profile_id, profile_type)
            self.db.set_one(self.db_collection, {"_id": content["_id"]}, content)
            self.db.del_one(self.db_collection, {"_id": content["_id"]})
        self.logger.info(
            f"Infra Controller Delete Exit with resource status: {resource_status}"
        )
        return


class K8sInfraConfigLcm(GitOpsLcm):
    db_collection = "k8sinfra_config"

    def __init__(self, msg, lcm_tasks, config):
        """
        Init, Connect to database, filesystem storage, and messaging
        :param config: two level dictionary with configuration. Top level should contain 'database', 'storage',
        :return: None
        """
        super().__init__(msg, lcm_tasks, config)

    async def create(self, params, order_id):
        self.logger.info("Infra config Create Enter")

        op_id = params["operation_id"]
        profile_id = params["profile_id"]

        # To initialize the operation states
        self.initialize_operation(profile_id, op_id)

        content = self.db.get_one("k8sinfra_config", {"_id": profile_id})
        content["profile_type"] = "infra-configs"
        op_params = self.get_operation_params(content, op_id)
        self.db.set_one("k8sinfra_config", {"_id": content["_id"]}, content)

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "create_profile", op_id, op_params, content
        )
        self.logger.info("workflow_name is: {}".format(workflow_name))

        workflow_status = await self.check_workflow_and_update_db(
            op_id, workflow_name, content
        )

        if workflow_status:
            resource_status, content = await self.check_resource_and_update_db(
                "create_profile", op_id, op_params, content
            )
        self.db.set_one(self.db_collection, {"_id": content["_id"]}, content)
        self.logger.info(
            f"Infra Config Create Exit with resource status: {resource_status}"
        )
        return

    async def delete(self, params, order_id):
        self.logger.info("Infra config delete Enter")

        op_id = params["operation_id"]
        profile_id = params["profile_id"]

        # To initialize the operation states
        self.initialize_operation(profile_id, op_id)

        content = self.db.get_one("k8sinfra_config", {"_id": profile_id})
        op_params = self.get_operation_params(content, op_id)

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "delete_profile", op_id, op_params, content
        )
        self.logger.info("workflow_name is: {}".format(workflow_name))

        workflow_status = await self.check_workflow_and_update_db(
            op_id, workflow_name, content
        )

        if workflow_status:
            resource_status, content = await self.check_resource_and_update_db(
                "delete_profile", op_id, op_params, content
            )

        force = params.get("force", False)
        if force:
            force_delete_status = self.check_force_delete_and_delete_from_db(
                profile_id, workflow_status, resource_status, force
            )
            if force_delete_status:
                return

        if resource_status:
            content["state"] = "DELETED"
            profile_type = self.profile_type_mapping[content["profile_type"]]
            self.delete_profile_ksu(profile_id, profile_type)
            self.db.set_one(self.db_collection, {"_id": content["_id"]}, content)
            self.db.del_one(self.db_collection, {"_id": content["_id"]})
        self.logger.info(
            f"Infra Config Delete Exit with resource status: {resource_status}"
        )

        return


class OkaLcm(GitOpsLcm):
    db_collection = "okas"

    def __init__(self, msg, lcm_tasks, config):
        """
        Init, Connect to database, filesystem storage, and messaging
        :param config: two level dictionary with configuration. Top level should contain 'database', 'storage',
        :return: None
        """
        super().__init__(msg, lcm_tasks, config)

    async def create(self, params, order_id):
        self.logger.info("OKA Create Enter")
        op_id = params["operation_id"]
        oka_id = params["oka_id"]
        self.initialize_operation(oka_id, op_id)
        db_content = self.db.get_one(self.db_collection, {"_id": oka_id})
        op_params = self.get_operation_params(db_content, op_id)

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "create_oka", op_id, op_params, db_content
        )

        workflow_status = await self.check_workflow_and_update_db(
            op_id, workflow_name, db_content
        )

        if workflow_status:
            resource_status, db_content = await self.check_resource_and_update_db(
                "create_oka", op_id, op_params, db_content
            )
        self.db.set_one(self.db_collection, {"_id": db_content["_id"]}, db_content)

        # Clean items used in the workflow, no matter if the workflow succeeded
        clean_status, clean_msg = await self.odu.clean_items_workflow(
            "create_oka", op_id, op_params, db_content
        )
        self.logger.info(
            f"clean_status is :{clean_status} and clean_msg is :{clean_msg}"
        )
        self.logger.info(f"OKA Create Exit with resource status: {resource_status}")
        return

    async def edit(self, params, order_id):
        self.logger.info("OKA Edit Enter")
        op_id = params["operation_id"]
        oka_id = params["oka_id"]
        self.initialize_operation(oka_id, op_id)
        db_content = self.db.get_one(self.db_collection, {"_id": oka_id})
        op_params = self.get_operation_params(db_content, op_id)

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "update_oka", op_id, op_params, db_content
        )
        workflow_status = await self.check_workflow_and_update_db(
            op_id, workflow_name, db_content
        )

        if workflow_status:
            resource_status, db_content = await self.check_resource_and_update_db(
                "update_oka", op_id, op_params, db_content
            )
        self.db.set_one(self.db_collection, {"_id": db_content["_id"]}, db_content)
        # Clean items used in the workflow, no matter if the workflow succeeded
        clean_status, clean_msg = await self.odu.clean_items_workflow(
            "update_oka", op_id, op_params, db_content
        )
        self.logger.info(
            f"clean_status is :{clean_status} and clean_msg is :{clean_msg}"
        )
        self.logger.info(f"OKA Update Exit with resource status: {resource_status}")
        return

    async def delete(self, params, order_id):
        self.logger.info("OKA delete Enter")
        op_id = params["operation_id"]
        oka_id = params["oka_id"]
        self.initialize_operation(oka_id, op_id)
        db_content = self.db.get_one(self.db_collection, {"_id": oka_id})
        op_params = self.get_operation_params(db_content, op_id)

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "delete_oka", op_id, op_params, db_content
        )
        workflow_status = await self.check_workflow_and_update_db(
            op_id, workflow_name, db_content
        )

        if workflow_status:
            resource_status, db_content = await self.check_resource_and_update_db(
                "delete_oka", op_id, op_params, db_content
            )

        force = params.get("force", False)
        if force:
            force_delete_status = self.check_force_delete_and_delete_from_db(
                oka_id, workflow_status, resource_status, force
            )
            if force_delete_status:
                return

        if resource_status:
            db_content["state"] == "DELETED"
            self.db.set_one(self.db_collection, {"_id": db_content["_id"]}, db_content)
            self.db.del_one(self.db_collection, {"_id": db_content["_id"]})
        # Clean items used in the workflow, no matter if the workflow succeeded
        clean_status, clean_msg = await self.odu.clean_items_workflow(
            "delete_oka", op_id, op_params, db_content
        )
        self.logger.info(
            f"clean_status is :{clean_status} and clean_msg is :{clean_msg}"
        )
        self.logger.info(f"OKA Delete Exit with resource status: {resource_status}")
        return


class KsuLcm(GitOpsLcm):
    db_collection = "ksus"

    def __init__(self, msg, lcm_tasks, config):
        """
        Init, Connect to database, filesystem storage, and messaging
        :param config: two level dictionary with configuration. Top level should contain 'database', 'storage',
        :return: None
        """
        super().__init__(msg, lcm_tasks, config)
        self._workflows = {
            "create_ksus": {
                "check_resource_function": self.check_create_ksus,
            },
            "delete_ksus": {
                "check_resource_function": self.check_delete_ksus,
            },
        }

    def get_dbclusters_from_profile(self, profile_id, profile_type):
        cluster_list = []
        db_clusters = self.db.get_list("clusters")
        self.logger.info(f"Getting list of clusters for {profile_type} {profile_id}")
        for db_cluster in db_clusters:
            if profile_id in db_cluster.get(profile_type, []):
                self.logger.info(
                    f"Profile {profile_id} found in cluster {db_cluster['name']}"
                )
                cluster_list.append(db_cluster)
        return cluster_list

    async def create(self, params, order_id):
        self.logger.info("ksu Create Enter")
        db_content = []
        op_params = []
        op_id = params["operation_id"]
        for ksu_id in params["ksus_list"]:
            self.logger.info("Ksu ID: {}".format(ksu_id))
            self.initialize_operation(ksu_id, op_id)
            db_ksu = self.db.get_one(self.db_collection, {"_id": ksu_id})
            self.logger.info("Db KSU: {}".format(db_ksu))
            db_content.append(db_ksu)
            ksu_params = {}
            ksu_params = self.get_operation_params(db_ksu, op_id)
            self.logger.info("Operation Params: {}".format(ksu_params))
            # Update ksu_params["profile"] with profile name and age-pubkey
            profile_type = ksu_params["profile"]["profile_type"]
            profile_id = ksu_params["profile"]["_id"]
            profile_collection = self.profile_collection_mapping[profile_type]
            db_profile = self.db.get_one(profile_collection, {"_id": profile_id})
            # db_profile is decrypted inline
            # No need to use decrypted_copy because db_profile won't be updated.
            self.decrypt_age_keys(db_profile)
            ksu_params["profile"]["name"] = db_profile["name"]
            ksu_params["profile"]["age_pubkey"] = db_profile.get("age_pubkey", "")
            # Update ksu_params["oka"] with sw_catalog_path (when missing)
            # TODO: remove this in favor of doing it in ODU workflow
            for oka in ksu_params["oka"]:
                if "sw_catalog_path" not in oka:
                    oka_id = oka["_id"]
                    db_oka = self.db.get_one("okas", {"_id": oka_id})
                    oka_type = MAP_PROFILE[
                        db_oka.get("profile_type", "infra_controller_profiles")
                    ]
                    oka[
                        "sw_catalog_path"
                    ] = f"{oka_type}/{db_oka['git_name'].lower()}/templates"
            op_params.append(ksu_params)

        # A single workflow is launched for all KSUs
        workflow_res, workflow_name = await self.odu.launch_workflow(
            "create_ksus", op_id, op_params, db_content
        )
        # Update workflow status in all KSUs
        wf_status_list = []
        for db_ksu, ksu_params in zip(db_content, op_params):
            workflow_status = await self.check_workflow_and_update_db(
                op_id, workflow_name, db_ksu
            )
            wf_status_list.append(workflow_status)
        # Update resource status in all KSUs
        # TODO: Is an operation correct if n KSUs are right and 1 is not OK?
        res_status_list = []
        for db_ksu, ksu_params, wf_status in zip(db_content, op_params, wf_status_list):
            if wf_status:
                resource_status, db_ksu = await self.check_resource_and_update_db(
                    "create_ksus", op_id, ksu_params, db_ksu
                )
            else:
                resource_status = False
            res_status_list.append(resource_status)
            self.db.set_one(self.db_collection, {"_id": db_ksu["_id"]}, db_ksu)

        # Clean items used in the workflow, no matter if the workflow succeeded
        clean_status, clean_msg = await self.odu.clean_items_workflow(
            "create_ksus", op_id, op_params, db_content
        )
        self.logger.info(
            f"clean_status is :{clean_status} and clean_msg is :{clean_msg}"
        )
        self.logger.info(f"KSU Create EXIT with Resource Status {res_status_list}")
        return

    async def edit(self, params, order_id):
        self.logger.info("ksu edit Enter")
        db_content = []
        op_params = []
        op_id = params["operation_id"]
        for ksu_id in params["ksus_list"]:
            self.initialize_operation(ksu_id, op_id)
            db_ksu = self.db.get_one("ksus", {"_id": ksu_id})
            db_content.append(db_ksu)
            ksu_params = {}
            ksu_params = self.get_operation_params(db_ksu, op_id)
            # Update ksu_params["profile"] with profile name and age-pubkey
            profile_type = ksu_params["profile"]["profile_type"]
            profile_id = ksu_params["profile"]["_id"]
            profile_collection = self.profile_collection_mapping[profile_type]
            db_profile = self.db.get_one(profile_collection, {"_id": profile_id})
            # db_profile is decrypted inline
            # No need to use decrypted_copy because db_profile won't be updated.
            self.decrypt_age_keys(db_profile)
            ksu_params["profile"]["name"] = db_profile["name"]
            ksu_params["profile"]["age_pubkey"] = db_profile.get("age_pubkey", "")
            # Update ksu_params["oka"] with sw_catalog_path (when missing)
            # TODO: remove this in favor of doing it in ODU workflow
            for oka in ksu_params["oka"]:
                if "sw_catalog_path" not in oka:
                    oka_id = oka["_id"]
                    db_oka = self.db.get_one("okas", {"_id": oka_id})
                    oka_type = MAP_PROFILE[
                        db_oka.get("profile_type", "infra_controller_profiles")
                    ]
                    oka[
                        "sw_catalog_path"
                    ] = f"{oka_type}/{db_oka['git_name']}/templates"
            op_params.append(ksu_params)

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "update_ksus", op_id, op_params, db_content
        )

        for db_ksu, ksu_params in zip(db_content, op_params):
            workflow_status = await self.check_workflow_and_update_db(
                op_id, workflow_name, db_ksu
            )

            if workflow_status:
                resource_status, db_ksu = await self.check_resource_and_update_db(
                    "update_ksus", op_id, ksu_params, db_ksu
                )
                db_ksu["name"] = ksu_params["name"]
                db_ksu["description"] = ksu_params["description"]
                db_ksu["profile"]["profile_type"] = ksu_params["profile"][
                    "profile_type"
                ]
                db_ksu["profile"]["_id"] = ksu_params["profile"]["_id"]
                db_ksu["oka"] = ksu_params["oka"]
            self.db.set_one(self.db_collection, {"_id": db_ksu["_id"]}, db_ksu)

        # Clean items used in the workflow, no matter if the workflow succeeded
        clean_status, clean_msg = await self.odu.clean_items_workflow(
            "create_ksus", op_id, op_params, db_content
        )
        self.logger.info(
            f"clean_status is :{clean_status} and clean_msg is :{clean_msg}"
        )
        self.logger.info(f"KSU Update EXIT with Resource Status {resource_status}")
        return

    async def delete(self, params, order_id):
        self.logger.info("ksu delete Enter")
        db_content = []
        op_params = []
        op_id = params["operation_id"]
        for ksu_id in params["ksus_list"]:
            self.initialize_operation(ksu_id, op_id)
            db_ksu = self.db.get_one("ksus", {"_id": ksu_id})
            db_content.append(db_ksu)
            ksu_params = {}
            ksu_params["profile"] = {}
            ksu_params["profile"]["profile_type"] = db_ksu["profile"]["profile_type"]
            ksu_params["profile"]["_id"] = db_ksu["profile"]["_id"]
            # Update ksu_params["profile"] with profile name
            profile_type = ksu_params["profile"]["profile_type"]
            profile_id = ksu_params["profile"]["_id"]
            profile_collection = self.profile_collection_mapping[profile_type]
            db_profile = self.db.get_one(profile_collection, {"_id": profile_id})
            ksu_params["profile"]["name"] = db_profile["name"]
            op_params.append(ksu_params)

        workflow_res, workflow_name = await self.odu.launch_workflow(
            "delete_ksus", op_id, op_params, db_content
        )

        for db_ksu, ksu_params in zip(db_content, op_params):
            workflow_status = await self.check_workflow_and_update_db(
                op_id, workflow_name, db_ksu
            )

            if workflow_status:
                resource_status, db_ksu = await self.check_resource_and_update_db(
                    "delete_ksus", op_id, ksu_params, db_ksu
                )

            force = params.get("force", False)
            if force:
                force_delete_status = self.check_force_delete_and_delete_from_db(
                    db_ksu["_id"], workflow_status, resource_status, force
                )
                if force_delete_status:
                    return

            if resource_status:
                db_ksu["state"] == "DELETED"
                self.db.set_one(self.db_collection, {"_id": db_ksu["_id"]}, db_ksu)
                self.db.del_one(self.db_collection, {"_id": db_ksu["_id"]})

        self.logger.info(f"KSU Delete Exit with resource status: {resource_status}")
        return

    async def clone(self, params, order_id):
        self.logger.info("ksu clone Enter")
        op_id = params["operation_id"]
        ksus_id = params["ksus_list"][0]
        self.initialize_operation(ksus_id, op_id)
        db_content = self.db.get_one(self.db_collection, {"_id": ksus_id})
        op_params = self.get_operation_params(db_content, op_id)
        workflow_res, workflow_name = await self.odu.launch_workflow(
            "clone_ksus", op_id, op_params, db_content
        )

        workflow_status = await self.check_workflow_and_update_db(
            op_id, workflow_name, db_content
        )

        if workflow_status:
            resource_status, db_content = await self.check_resource_and_update_db(
                "clone_ksus", op_id, op_params, db_content
            )
        self.db.set_one(self.db_collection, {"_id": db_content["_id"]}, db_content)

        self.logger.info(f"KSU Clone Exit with resource status: {resource_status}")
        return

    async def move(self, params, order_id):
        self.logger.info("ksu move Enter")
        op_id = params["operation_id"]
        ksus_id = params["ksus_list"][0]
        self.initialize_operation(ksus_id, op_id)
        db_content = self.db.get_one(self.db_collection, {"_id": ksus_id})
        op_params = self.get_operation_params(db_content, op_id)
        workflow_res, workflow_name = await self.odu.launch_workflow(
            "move_ksus", op_id, op_params, db_content
        )

        workflow_status = await self.check_workflow_and_update_db(
            op_id, workflow_name, db_content
        )

        if workflow_status:
            resource_status, db_content = await self.check_resource_and_update_db(
                "move_ksus", op_id, op_params, db_content
            )
        self.db.set_one(self.db_collection, {"_id": db_content["_id"]}, db_content)

        self.logger.info(f"KSU Move Exit with resource status: {resource_status}")
        return

    async def check_create_ksus(self, op_id, op_params, content):
        self.logger.info(f"check_create_ksus Operation {op_id}. Params: {op_params}.")
        self.logger.debug(f"Content: {content}")
        db_ksu = content
        kustomization_name = db_ksu["git_name"].lower()
        oka_list = op_params["oka"]
        oka_item = oka_list[0]
        oka_params = oka_item.get("transformation", {})
        kustomization_ns = oka_params.get("kustomization_namespace", "flux-system")
        profile_id = op_params.get("profile", {}).get("_id")
        profile_type = op_params.get("profile", {}).get("profile_type")
        self.logger.info(
            f"Checking status of KSU {db_ksu['name']} for profile {profile_id}."
        )
        dbcluster_list = self.get_dbclusters_from_profile(profile_id, profile_type)
        if not dbcluster_list:
            self.logger.info(f"No clusters found for profile {profile_id}.")
        for db_cluster in dbcluster_list:
            try:
                self.logger.info(
                    f"Checking status of KSU {db_ksu['name']} in cluster {db_cluster['name']}."
                )
                cluster_kubectl = self.cluster_kubectl(db_cluster)
                checkings_list = [
                    {
                        "item": "kustomization",
                        "name": kustomization_name,
                        "namespace": kustomization_ns,
                        "condition": {
                            "jsonpath_filter": "status.conditions[?(@.type=='Ready')].status",
                            "value": "True",
                        },
                        "timeout": self._checkloop_kustomization_timeout,
                        "enable": True,
                        "resourceState": "IN_PROGRESS.KUSTOMIZATION_READY",
                    },
                ]
                self.logger.info(
                    f"Checking status of KSU {db_ksu['name']} for profile {profile_id}."
                )
                result, message = await self.common_check_list(
                    op_id, checkings_list, "ksus", db_ksu, kubectl_obj=cluster_kubectl
                )
                if not result:
                    return False, message
            except Exception as e:
                self.logger.error(
                    f"Error checking KSU in cluster {db_cluster['name']}."
                )
                self.logger.error(e)
                return False, f"Error checking KSU in cluster {db_cluster['name']}."
        return True, "OK"

    async def check_delete_ksus(self, op_id, op_params, content):
        self.logger.info(f"check_delete_ksus Operation {op_id}. Params: {op_params}.")
        self.logger.debug(f"Content: {content}")
        db_ksu = content
        kustomization_name = db_ksu["git_name"].lower()
        oka_list = db_ksu["oka"]
        oka_item = oka_list[0]
        oka_params = oka_item.get("transformation", {})
        kustomization_ns = oka_params.get("kustomization_namespace", "flux-system")
        profile_id = op_params.get("profile", {}).get("_id")
        profile_type = op_params.get("profile", {}).get("profile_type")
        self.logger.info(
            f"Checking status of KSU {db_ksu['name']} for profile {profile_id}."
        )
        dbcluster_list = self.get_dbclusters_from_profile(profile_id, profile_type)
        if not dbcluster_list:
            self.logger.info(f"No clusters found for profile {profile_id}.")
        for db_cluster in dbcluster_list:
            try:
                self.logger.info(
                    f"Checking status of KSU in cluster {db_cluster['name']}."
                )
                cluster_kubectl = self.cluster_kubectl(db_cluster)
                checkings_list = [
                    {
                        "item": "kustomization",
                        "name": kustomization_name,
                        "namespace": kustomization_ns,
                        "deleted": True,
                        "timeout": self._checkloop_kustomization_timeout,
                        "enable": True,
                        "resourceState": "IN_PROGRESS.KUSTOMIZATION_DELETED",
                    },
                ]
                self.logger.info(
                    f"Checking status of KSU {db_ksu['name']} for profile {profile_id}."
                )
                result, message = await self.common_check_list(
                    op_id, checkings_list, "ksus", db_ksu, kubectl_obj=cluster_kubectl
                )
                if not result:
                    return False, message
            except Exception as e:
                self.logger.error(
                    f"Error checking KSU in cluster {db_cluster['name']}."
                )
                self.logger.error(e)
                return False, f"Error checking KSU in cluster {db_cluster['name']}."
        return True, "OK"
