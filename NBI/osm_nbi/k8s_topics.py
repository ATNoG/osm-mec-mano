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

import logging
import yaml
import shutil
import os
from http import HTTPStatus

from time import time
from osm_nbi.base_topic import BaseTopic, EngineException
from osm_nbi.acm_topic import ACMTopic, ACMOperationTopic, ProfileTopic

from osm_nbi.descriptor_topics import DescriptorTopic
from osm_nbi.validation import (
    ValidationError,
    validate_input,
    clustercreation_new_schema,
    cluster_edit_schema,
    cluster_update_schema,
    infra_controller_profile_create_new_schema,
    infra_config_profile_create_new_schema,
    app_profile_create_new_schema,
    resource_profile_create_new_schema,
    infra_controller_profile_create_edit_schema,
    infra_config_profile_create_edit_schema,
    app_profile_create_edit_schema,
    resource_profile_create_edit_schema,
    clusterregistration_new_schema,
    attach_dettach_profile_schema,
    ksu_schema,
    oka_schema,
)
from osm_common.dbbase import deep_update_rfc7396, DbException
from osm_common.msgbase import MsgException
from osm_common.fsbase import FsException

__author__ = (
    "Shrinithi R <shrinithi.r@tataelxsi.co.in>",
    "Shahithya Y <shahithya.y@tataelxsi.co.in>",
)


class InfraContTopic(ProfileTopic):
    topic = "k8sinfra_controller"
    topic_msg = "k8s_infra_controller"
    schema_new = infra_controller_profile_create_new_schema
    schema_edit = infra_controller_profile_create_edit_schema

    def __init__(self, db, fs, msg, auth):
        BaseTopic.__init__(self, db, fs, msg, auth)

    def new(self, rollback, session, indata=None, kwargs=None, headers=None):
        # To create the new infra controller profile
        return self.new_profile(rollback, session, indata, kwargs, headers)

    def default(self, rollback, session, indata=None, kwargs=None, headers=None):
        # To create the default infra controller profile while creating the cluster
        return self.default_profile(rollback, session, indata, kwargs, headers)

    def delete(self, session, _id, dry_run=False, not_send_msg=None):
        self.delete_profile(session, _id, dry_run=False, not_send_msg=None)
        return _id


class InfraConfTopic(ProfileTopic):
    topic = "k8sinfra_config"
    topic_msg = "k8s_infra_config"
    schema_new = infra_config_profile_create_new_schema
    schema_edit = infra_config_profile_create_edit_schema

    def __init__(self, db, fs, msg, auth):
        BaseTopic.__init__(self, db, fs, msg, auth)

    def new(self, rollback, session, indata=None, kwargs=None, headers=None):
        # To create the new infra config profile
        return self.new_profile(rollback, session, indata, kwargs, headers)

    def default(self, rollback, session, indata=None, kwargs=None, headers=None):
        # To create the default infra config profile while creating the cluster
        return self.default_profile(rollback, session, indata, kwargs, headers)

    def delete(self, session, _id, dry_run=False, not_send_msg=None):
        self.delete_profile(session, _id, dry_run=False, not_send_msg=None)
        return _id


class AppTopic(ProfileTopic):
    topic = "k8sapp"
    topic_msg = "k8s_app"
    schema_new = app_profile_create_new_schema
    schema_edit = app_profile_create_edit_schema

    def __init__(self, db, fs, msg, auth):
        BaseTopic.__init__(self, db, fs, msg, auth)

    def new(self, rollback, session, indata=None, kwargs=None, headers=None):
        # To create the new app profile
        return self.new_profile(rollback, session, indata, kwargs, headers)

    def default(self, rollback, session, indata=None, kwargs=None, headers=None):
        # To create the default app profile while creating the cluster
        return self.default_profile(rollback, session, indata, kwargs, headers)

    def delete(self, session, _id, dry_run=False, not_send_msg=None):
        self.delete_profile(session, _id, dry_run=False, not_send_msg=None)
        return _id


class ResourceTopic(ProfileTopic):
    topic = "k8sresource"
    topic_msg = "k8s_resource"
    schema_new = resource_profile_create_new_schema
    schema_edit = resource_profile_create_edit_schema

    def __init__(self, db, fs, msg, auth):
        BaseTopic.__init__(self, db, fs, msg, auth)

    def new(self, rollback, session, indata=None, kwargs=None, headers=None):
        # To create the new resource profile
        return self.new_profile(rollback, session, indata, kwargs, headers)

    def default(self, rollback, session, indata=None, kwargs=None, headers=None):
        # To create the default resource profile while creating the cluster
        return self.default_profile(rollback, session, indata, kwargs, headers)

    def delete(self, session, _id, dry_run=False, not_send_msg=None):
        self.delete_profile(session, _id, dry_run=False, not_send_msg=None)
        return _id


class ClusterTopic(ACMTopic):
    topic = "clusters"
    topic_msg = "cluster"
    schema_new = clustercreation_new_schema
    schema_edit = attach_dettach_profile_schema

    def __init__(self, db, fs, msg, auth):
        super().__init__(db, fs, msg, auth)
        self.infra_contr_topic = InfraContTopic(db, fs, msg, auth)
        self.infra_conf_topic = InfraConfTopic(db, fs, msg, auth)
        self.resource_topic = ResourceTopic(db, fs, msg, auth)
        self.app_topic = AppTopic(db, fs, msg, auth)

    @staticmethod
    def format_on_new(content, project_id=None, make_public=False):
        ACMTopic.format_on_new(content, project_id=project_id, make_public=make_public)
        content["current_operation"] = None

    def new(self, rollback, session, indata=None, kwargs=None, headers=None):
        """
        Creates a new k8scluster into database.
        :param rollback: list to append the created items at database in case a rollback must be done
        :param session: contains "username", "admin", "force", "public", "project_id", "set_project"
        :param indata: params to be used for the k8cluster
        :param kwargs: used to override the indata
        :param headers: http request headers
        :return: the _id of k8scluster created at database. Or an exception of type
            EngineException, ValidationError, DbException, FsException, MsgException.
            Note: Exceptions are not captured on purpose. They should be captured at called
        """
        step = "checking quotas"  # first step must be defined outside try
        try:
            self.check_quota(session)
            step = "name unique check"
            # self.check_unique_name(session, indata["name"])
            self.cluster_unique_name_check(session, indata["name"])
            step = "validating input parameters"
            cls_request = self._remove_envelop(indata)
            self._update_input_with_kwargs(cls_request, kwargs)
            cls_request = self._validate_input_new(cls_request, session["force"])
            operation_params = cls_request

            step = "filling cluster details from input data"
            cls_create = self._create_cluster(
                cls_request, rollback, session, indata, kwargs, headers
            )

            step = "creating cluster at database"
            self.format_on_new(
                cls_create, session["project_id"], make_public=session["public"]
            )
            op_id = self.format_on_operation(
                cls_create,
                "create",
                operation_params,
            )
            _id = self.db.create(self.topic, cls_create)
            pubkey, privkey = self._generate_age_key()
            cls_create["age_pubkey"] = self.db.encrypt(
                pubkey, schema_version="1.11", salt=_id
            )
            cls_create["age_privkey"] = self.db.encrypt(
                privkey, schema_version="1.11", salt=_id
            )
            # TODO: set age_pubkey and age_privkey in the default profiles
            rollback.append({"topic": self.topic, "_id": _id})
            self.db.set_one("clusters", {"_id": _id}, cls_create)
            self._send_msg("create", {"cluster_id": _id, "operation_id": op_id})

            # To add the content in old collection "k8sclusters"
            self.add_to_old_collection(cls_create, session)

            return _id, None
        except (
            ValidationError,
            EngineException,
            DbException,
            MsgException,
            FsException,
        ) as e:
            raise type(e)("{} while '{}'".format(e, step), http_code=e.http_code)

    def _create_cluster(self, cls_request, rollback, session, indata, kwargs, headers):
        # Check whether the region name and resource group have been given
        region_given = "region_name" in indata
        resource_group_given = "resource_group" in indata

        # Get the vim_account details
        vim_account_details = self.db.get_one(
            "vim_accounts", {"name": cls_request["vim_account"]}
        )

        # Check whether the region name and resource group have been given
        if not region_given and not resource_group_given:
            region_name = vim_account_details["config"]["region_name"]
            resource_group = vim_account_details["config"]["resource_group"]
        elif region_given and not resource_group_given:
            region_name = cls_request["region_name"]
            resource_group = vim_account_details["config"]["resource_group"]
        elif not region_given and resource_group_given:
            region_name = vim_account_details["config"]["region_name"]
            resource_group = cls_request["resource_group"]
        else:
            region_name = cls_request["region_name"]
            resource_group = cls_request["resource_group"]

        cls_desc = {
            "name": cls_request["name"],
            "vim_account": self.check_vim(session, cls_request["vim_account"]),
            "k8s_version": cls_request["k8s_version"],
            "node_size": cls_request["node_size"],
            "node_count": cls_request["node_count"],
            "bootstrap": cls_request["bootstrap"],
            "region_name": region_name,
            "resource_group": resource_group,
            "infra_controller_profiles": [
                self._create_default_profiles(
                    rollback, session, indata, kwargs, headers, self.infra_contr_topic
                )
            ],
            "infra_config_profiles": [
                self._create_default_profiles(
                    rollback, session, indata, kwargs, headers, self.infra_conf_topic
                )
            ],
            "resource_profiles": [
                self._create_default_profiles(
                    rollback, session, indata, kwargs, headers, self.resource_topic
                )
            ],
            "app_profiles": [
                self._create_default_profiles(
                    rollback, session, indata, kwargs, headers, self.app_topic
                )
            ],
            "created": "true",
            "state": "IN_CREATION",
            "operatingState": "PROCESSING",
            "git_name": self.create_gitname(cls_request, session),
            "resourceState": "IN_PROGRESS.REQUEST_RECEIVED",
        }
        # Add optional fields if they exist in the request
        if "description" in cls_request:
            cls_desc["description"] = cls_request["description"]
        return cls_desc

    def check_vim(self, session, name):
        try:
            vim_account_details = self.db.get_one("vim_accounts", {"name": name})
            if vim_account_details is not None:
                return name
        except ValidationError as e:
            raise EngineException(
                e,
                HTTPStatus.UNPROCESSABLE_ENTITY,
            )

    def _create_default_profiles(
        self, rollback, session, indata, kwargs, headers, topic
    ):
        topic = self.to_select_topic(topic)
        default_profiles = topic.default(rollback, session, indata, kwargs, headers)
        return default_profiles

    def to_select_topic(self, topic):
        if topic == "infra_controller_profiles":
            topic = self.infra_contr_topic
        elif topic == "infra_config_profiles":
            topic = self.infra_conf_topic
        elif topic == "resource_profiles":
            topic = self.resource_topic
        elif topic == "app_profiles":
            topic = self.app_topic
        return topic

    def show_one(self, session, _id, profile, filter_q=None, api_req=False):
        try:
            filter_q = self._get_project_filter(session)
            filter_q[self.id_field(self.topic, _id)] = _id
            content = self.db.get_one(self.topic, filter_q)
            existing_profiles = []
            topic = None
            topic = self.to_select_topic(profile)
            for profile_id in content[profile]:
                data = topic.show(session, profile_id, filter_q, api_req)
                existing_profiles.append(data)
            return existing_profiles
        except ValidationError as e:
            raise EngineException(e, HTTPStatus.UNPROCESSABLE_ENTITY)

    def state_check(self, profile_id, session, topic):
        topic = self.to_select_topic(topic)
        content = topic.show(session, profile_id, filter_q=None, api_req=False)
        state = content["state"]
        if state == "CREATED":
            return
        else:
            raise EngineException(
                f" {profile_id}  is not in created state",
                HTTPStatus.UNPROCESSABLE_ENTITY,
            )

    def edit(self, session, _id, item, indata=None, kwargs=None):
        if item not in (
            "infra_controller_profiles",
            "infra_config_profiles",
            "app_profiles",
            "resource_profiles",
        ):
            self.schema_edit = cluster_edit_schema
            super().edit(session, _id, indata=item, kwargs=kwargs, content=None)
        else:
            indata = self._remove_envelop(indata)
            indata = self._validate_input_edit(
                indata, content=None, force=session["force"]
            )
            if indata.get("add_profile"):
                self.add_profile(session, _id, item, indata)
            elif indata.get("remove_profile"):
                self.remove_profile(session, _id, item, indata)
            else:
                error_msg = "Add / remove operation is only applicable"
                raise EngineException(error_msg, HTTPStatus.UNPROCESSABLE_ENTITY)

    def edit_extra_before(self, session, _id, indata=None, kwargs=None, content=None):
        check = self.db.get_one(self.topic, {"_id": _id})
        if "name" in indata and check["name"] != indata["name"]:
            self.check_unique_name(session, indata["name"])
            _filter = {"name": indata["name"]}
            topic_list = [
                "k8sclusters",
                "k8sinfra_controller",
                "k8sinfra_config",
                "k8sapp",
                "k8sresource",
            ]
            # Check unique name for k8scluster and profiles
            for topic in topic_list:
                if self.db.get_one(
                    topic, _filter, fail_on_empty=False, fail_on_more=False
                ):
                    raise EngineException(
                        "name '{}' already exists for {}".format(indata["name"], topic),
                        HTTPStatus.CONFLICT,
                    )
            # Replace name in k8scluster and profiles
            for topic in topic_list:
                data = self.db.get_one(topic, {"name": check["name"]})
                data["name"] = indata["name"]
                self.db.replace(topic, data["_id"], data)
        return True

    def add_profile(self, session, _id, item, indata=None):
        indata = self._remove_envelop(indata)
        operation_params = indata
        profile_id = indata["add_profile"][0]["id"]
        # check state
        self.state_check(profile_id, session, item)
        filter_q = self._get_project_filter(session)
        filter_q[self.id_field(self.topic, _id)] = _id
        content = self.db.get_one(self.topic, filter_q)
        profile_list = content[item]

        if profile_id not in profile_list:
            content["operatingState"] = "PROCESSING"
            op_id = self.format_on_operation(
                content,
                "add",
                operation_params,
            )
            self.db.set_one("clusters", {"_id": content["_id"]}, content)
            self._send_msg(
                "add",
                {
                    "cluster_id": _id,
                    "profile_id": profile_id,
                    "profile_type": item,
                    "operation_id": op_id,
                },
            )
        else:
            raise EngineException(
                f"{item} {profile_id} already exists", HTTPStatus.UNPROCESSABLE_ENTITY
            )

    def _get_default_profiles(self, session, topic):
        topic = self.to_select_topic(topic)
        existing_profiles = topic.list(session, filter_q=None, api_req=False)
        default_profiles = [
            profile["_id"]
            for profile in existing_profiles
            if profile.get("default", False)
        ]
        return default_profiles

    def remove_profile(self, session, _id, item, indata):
        indata = self._remove_envelop(indata)
        operation_params = indata
        profile_id = indata["remove_profile"][0]["id"]
        filter_q = self._get_project_filter(session)
        filter_q[self.id_field(self.topic, _id)] = _id
        content = self.db.get_one(self.topic, filter_q)
        profile_list = content[item]

        default_profiles = self._get_default_profiles(session, item)

        if profile_id in default_profiles:
            raise EngineException(
                "Cannot remove default profile", HTTPStatus.UNPROCESSABLE_ENTITY
            )
        if profile_id in profile_list:
            op_id = self.format_on_operation(
                content,
                "remove",
                operation_params,
            )
            self.db.set_one("clusters", {"_id": content["_id"]}, content)
            self._send_msg(
                "remove",
                {
                    "cluster_id": _id,
                    "profile_id": profile_id,
                    "profile_type": item,
                    "operation_id": op_id,
                },
            )
        else:
            raise EngineException(
                f"{item} {profile_id} does'nt exists", HTTPStatus.UNPROCESSABLE_ENTITY
            )

    def get_cluster_creds(self, session, _id, item):
        if not self.multiproject:
            filter_db = {}
        else:
            filter_db = self._get_project_filter(session)
        filter_db[BaseTopic.id_field(self.topic, _id)] = _id
        operation_params = None
        data = self.db.get_one(self.topic, filter_db)
        op_id = self.format_on_operation(data, item, operation_params)
        self.db.set_one(self.topic, {"_id": data["_id"]}, data)
        self._send_msg("get_creds", {"cluster_id": _id, "operation_id": op_id})
        return op_id

    def get_cluster_creds_file(self, session, _id, item, op_id):
        if not self.multiproject:
            filter_db = {}
        else:
            filter_db = self._get_project_filter(session)
        filter_db[BaseTopic.id_field(self.topic, _id)] = _id

        data = self.db.get_one(self.topic, filter_db)
        creds_flag = None
        for operations in data["operationHistory"]:
            if operations["op_id"] == op_id:
                creds_flag = operations["result"]
        self.logger.info("Creds Flag: {}".format(creds_flag))

        if creds_flag is True:
            credentials = data["credentials"]

            file_pkg = None
            current_path = _id

            self.fs.file_delete(current_path, ignore_non_exist=True)
            self.fs.mkdir(current_path)
            filename = "credentials.yaml"
            file_path = (current_path, filename)
            self.logger.info("File path: {}".format(file_path))
            file_pkg = self.fs.file_open(file_path, "a+b")

            credentials_yaml = yaml.safe_dump(
                credentials, indent=4, default_flow_style=False
            )
            file_pkg.write(credentials_yaml.encode(encoding="utf-8"))

            if file_pkg:
                file_pkg.close()
            file_pkg = None
            self.fs.sync(from_path=current_path)

            return (
                self.fs.file_open((current_path, filename), "rb"),
                "text/plain",
            )
        else:
            raise EngineException(
                "Not possible to get the credentials of the cluster",
                HTTPStatus.UNPROCESSABLE_ENTITY,
            )

    def update_cluster(self, session, _id, item, indata):
        if not self.multiproject:
            filter_db = {}
        else:
            filter_db = self._get_project_filter(session)
        # To allow project&user addressing by name AS WELL AS _id
        filter_db[BaseTopic.id_field(self.topic, _id)] = _id
        validate_input(indata, cluster_update_schema)
        data = self.db.get_one(self.topic, filter_db)
        operation_params = {}
        data["operatingState"] = "PROCESSING"
        data["resourceState"] = "IN_PROGRESS"
        operation_params = indata
        op_id = self.format_on_operation(
            data,
            item,
            operation_params,
        )
        self.db.set_one(self.topic, {"_id": _id}, data)
        data = {"cluster_id": _id, "operation_id": op_id}
        self._send_msg(item, data)
        return op_id

    def delete_extra_before(self, session, _id, db_content, not_send_msg=None):
        op_id = self.common_delete(_id, db_content)
        return {"cluster_id": _id, "operation_id": op_id, "force": session["force"]}

    def delete(self, session, _id, dry_run=False, not_send_msg=None):
        filter_q = self._get_project_filter(session)
        filter_q[self.id_field(self.topic, _id)] = _id
        check = self.db.get_one(self.topic, filter_q)
        if check["created"] == "false":
            raise EngineException(
                "Cannot delete registered cluster. Please deregister.",
                HTTPStatus.UNPROCESSABLE_ENTITY,
            )
        super().delete(session, _id, dry_run=False, not_send_msg=None)


class ClusterOpsTopic(ACMTopic):
    topic = "clusters"
    topic_msg = "cluster"
    schema_new = clusterregistration_new_schema

    def __init__(self, db, fs, msg, auth):
        super().__init__(db, fs, msg, auth)

    @staticmethod
    def format_on_new(content, project_id=None, make_public=False):
        ACMTopic.format_on_new(content, project_id=project_id, make_public=make_public)
        content["current_operation"] = None

    def add(self, rollback, session, indata, kwargs=None, headers=None):
        step = "checking quotas"
        try:
            self.check_quota(session)
            step = "name unique check"
            self.cluster_unique_name_check(session, indata["name"])
            # self.check_unique_name(session, indata["name"])
            step = "validating input parameters"
            cls_add_request = self._remove_envelop(indata)
            self._update_input_with_kwargs(cls_add_request, kwargs)
            cls_add_request = self._validate_input_new(
                cls_add_request, session["force"]
            )
            operation_params = cls_add_request

            step = "filling cluster details from input data"
            cls_add_request = self._add_cluster(cls_add_request, session)

            step = "registering the cluster at database"
            self.format_on_new(
                cls_add_request, session["project_id"], make_public=session["public"]
            )
            op_id = self.format_on_operation(
                cls_add_request,
                "register",
                operation_params,
            )
            _id = self.db.create(self.topic, cls_add_request)
            pubkey, privkey = self._generate_age_key()
            cls_add_request["age_pubkey"] = self.db.encrypt(
                pubkey, schema_version="1.11", salt=_id
            )
            cls_add_request["age_privkey"] = self.db.encrypt(
                privkey, schema_version="1.11", salt=_id
            )
            # TODO: set age_pubkey and age_privkey in the default profiles
            self.db.set_one(self.topic, {"_id": _id}, cls_add_request)
            rollback.append({"topic": self.topic, "_id": _id})
            self._send_msg("register", {"cluster_id": _id, "operation_id": op_id})

            # To add the content in old collection "k8sclusters"
            self.add_to_old_collection(cls_add_request, session)

            return _id, None
        except (
            ValidationError,
            EngineException,
            DbException,
            MsgException,
            FsException,
        ) as e:
            raise type(e)("{} while '{}'".format(e, step), http_code=e.http_code)

    def _add_cluster(self, cls_add_request, session):
        cls_add = {
            "name": cls_add_request["name"],
            "credentials": cls_add_request["credentials"],
            "vim_account": cls_add_request["vim_account"],
            "bootstrap": cls_add_request["bootstrap"],
            "created": "false",
            "state": "IN_CREATION",
            "operatingState": "PROCESSING",
            "git_name": self.create_gitname(cls_add_request, session),
            "resourceState": "IN_PROGRESS.REQUEST_RECEIVED",
        }
        # Add optional fields if they exist in the request
        if "description" in cls_add_request:
            cls_add["description"] = cls_add_request["description"]
        return cls_add

    def remove(self, session, _id, dry_run=False, not_send_msg=None):
        """
        Delete item by its internal _id
        :param session: contains "username", "admin", "force", "public", "project_id", "set_project"
        :param _id: server internal id
        :param dry_run: make checking but do not delete
        :param not_send_msg: To not send message (False) or store content (list) instead
        :return: operation id (None if there is not operation), raise exception if error or not found, conflict, ...
        """

        # To allow addressing projects and users by name AS WELL AS by _id
        if not self.multiproject:
            filter_q = {}
        else:
            filter_q = self._get_project_filter(session)
        filter_q[self.id_field(self.topic, _id)] = _id
        item_content = self.db.get_one(self.topic, filter_q)

        op_id = self.format_on_operation(
            item_content,
            "deregister",
            None,
        )
        self.db.set_one(self.topic, {"_id": _id}, item_content)

        self.check_conflict_on_del(session, _id, item_content)
        if dry_run:
            return None

        if self.multiproject and session["project_id"]:
            # remove reference from project_read if there are more projects referencing it. If it last one,
            # do not remove reference, but delete
            other_projects_referencing = next(
                (
                    p
                    for p in item_content["_admin"]["projects_read"]
                    if p not in session["project_id"] and p != "ANY"
                ),
                None,
            )

            # check if there are projects referencing it (apart from ANY, that means, public)....
            if other_projects_referencing:
                # remove references but not delete
                update_dict_pull = {
                    "_admin.projects_read": session["project_id"],
                    "_admin.projects_write": session["project_id"],
                }
                self.db.set_one(
                    self.topic, filter_q, update_dict=None, pull_list=update_dict_pull
                )
                return None
            else:
                can_write = next(
                    (
                        p
                        for p in item_content["_admin"]["projects_write"]
                        if p == "ANY" or p in session["project_id"]
                    ),
                    None,
                )
                if not can_write:
                    raise EngineException(
                        "You have not write permission to delete it",
                        http_code=HTTPStatus.UNAUTHORIZED,
                    )

        # delete
        self._send_msg(
            "deregister",
            {"cluster_id": _id, "operation_id": op_id},
            not_send_msg=not_send_msg,
        )
        return None


class KsusTopic(ACMTopic):
    topic = "ksus"
    okapkg_topic = "okas"
    infra_topic = "k8sinfra"
    topic_msg = "ksu"
    schema_new = ksu_schema
    schema_edit = ksu_schema

    def __init__(self, db, fs, msg, auth):
        super().__init__(db, fs, msg, auth)
        self.logger = logging.getLogger("nbi.ksus")

    @staticmethod
    def format_on_new(content, project_id=None, make_public=False):
        BaseTopic.format_on_new(content, project_id=project_id, make_public=make_public)
        content["current_operation"] = None
        content["state"] = "IN_CREATION"
        content["operatingState"] = "PROCESSING"
        content["resourceState"] = "IN_PROGRESS"

    def new(self, rollback, session, indata=None, kwargs=None, headers=None):
        _id_list = []
        for ksus in indata["ksus"]:
            content = ksus
            oka = content["oka"][0]
            oka_flag = ""
            if oka["_id"]:
                oka_flag = "_id"
                oka["sw_catalog_path"] = ""
            elif oka["sw_catalog_path"]:
                oka_flag = "sw_catalog_path"

            for okas in content["oka"]:
                if okas["_id"] and okas["sw_catalog_path"]:
                    raise EngineException(
                        "Cannot create ksu with both OKA and SW catalog path",
                        HTTPStatus.UNPROCESSABLE_ENTITY,
                    )
                if not okas["sw_catalog_path"]:
                    okas.pop("sw_catalog_path")
                elif not okas["_id"]:
                    okas.pop("_id")
                if oka_flag not in okas.keys():
                    raise EngineException(
                        "Cannot create ksu. Give either OKA or SW catalog path for all oka in a KSU",
                        HTTPStatus.UNPROCESSABLE_ENTITY,
                    )

            # Override descriptor with query string kwargs
            content = self._remove_envelop(content)
            self._update_input_with_kwargs(content, kwargs)
            content = self._validate_input_new(input=content, force=session["force"])

            # Check for unique name
            self.check_unique_name(session, content["name"])

            self.check_conflict_on_new(session, content)

            operation_params = {}
            for content_key, content_value in content.items():
                operation_params[content_key] = content_value
            self.format_on_new(
                content, project_id=session["project_id"], make_public=session["public"]
            )
            op_id = self.format_on_operation(
                content,
                operation_type="create",
                operation_params=operation_params,
            )
            content["git_name"] = self.create_gitname(content, session)

            # Update Oka_package usage state
            for okas in content["oka"]:
                if "_id" in okas.keys():
                    self.update_usage_state(session, okas)

            _id = self.db.create(self.topic, content)
            rollback.append({"topic": self.topic, "_id": _id})
            _id_list.append(_id)
        data = {"ksus_list": _id_list, "operation_id": op_id}
        self._send_msg("create", data)
        return _id_list, op_id

    def clone(self, rollback, session, _id, indata, kwargs, headers):
        filter_db = self._get_project_filter(session)
        filter_db[BaseTopic.id_field(self.topic, _id)] = _id
        data = self.db.get_one(self.topic, filter_db)

        op_id = self.format_on_operation(
            data,
            "clone",
            indata,
        )
        self.db.set_one(self.topic, {"_id": data["_id"]}, data)
        self._send_msg("clone", {"ksus_list": [data["_id"]], "operation_id": op_id})
        return op_id

    def update_usage_state(self, session, oka_content):
        _id = oka_content["_id"]
        filter_db = self._get_project_filter(session)
        filter_db[BaseTopic.id_field(self.topic, _id)] = _id

        data = self.db.get_one(self.okapkg_topic, filter_db)
        if data["_admin"]["usageState"] == "NOT_IN_USE":
            usage_state_update = {
                "_admin.usageState": "IN_USE",
            }
            self.db.set_one(
                self.okapkg_topic, {"_id": _id}, update_dict=usage_state_update
            )

    def move_ksu(self, session, _id, indata=None, kwargs=None, content=None):
        indata = self._remove_envelop(indata)

        # Override descriptor with query string kwargs
        if kwargs:
            self._update_input_with_kwargs(indata, kwargs)
        try:
            if indata and session.get("set_project"):
                raise EngineException(
                    "Cannot edit content and set to project (query string SET_PROJECT) at same time",
                    HTTPStatus.UNPROCESSABLE_ENTITY,
                )
            # TODO self._check_edition(session, indata, _id, force)
            if not content:
                content = self.show(session, _id)
            indata = self._validate_input_edit(
                input=indata, content=content, force=session["force"]
            )
            operation_params = indata
            deep_update_rfc7396(content, indata)

            # To allow project addressing by name AS WELL AS _id. Get the _id, just in case the provided one is a name
            _id = content.get("_id") or _id
            op_id = self.format_on_operation(
                content,
                "move",
                operation_params,
            )
            if content.get("_admin"):
                now = time()
                content["_admin"]["modified"] = now
            content["operatingState"] = "PROCESSING"
            content["resourceState"] = "IN_PROGRESS"

            self.db.replace(self.topic, _id, content)
            data = {"ksus_list": [content["_id"]], "operation_id": op_id}
            self._send_msg("move", data)
            return op_id
        except ValidationError as e:
            raise EngineException(e, HTTPStatus.UNPROCESSABLE_ENTITY)

    def check_conflict_on_edit(self, session, final_content, edit_content, _id):
        if final_content["name"] != edit_content["name"]:
            self.check_unique_name(session, edit_content["name"])
        return final_content

    @staticmethod
    def format_on_edit(final_content, edit_content):
        op_id = ACMTopic.format_on_operation(
            final_content,
            "update",
            edit_content,
        )
        final_content["operatingState"] = "PROCESSING"
        final_content["resourceState"] = "IN_PROGRESS"
        if final_content.get("_admin"):
            now = time()
            final_content["_admin"]["modified"] = now
        return op_id

    def edit(self, session, _id, indata, kwargs):
        _id_list = []
        if _id == "update":
            for ksus in indata["ksus"]:
                content = ksus
                _id = content["_id"]
                _id_list.append(_id)
                content.pop("_id")
                op_id = self.edit_ksu(session, _id, content, kwargs)
        else:
            content = indata
            _id_list.append(_id)
            op_id = self.edit_ksu(session, _id, content, kwargs)

        data = {"ksus_list": _id_list, "operation_id": op_id}
        self._send_msg("edit", data)

    def edit_ksu(self, session, _id, indata, kwargs):
        content = None
        indata = self._remove_envelop(indata)

        # Override descriptor with query string kwargs
        if kwargs:
            self._update_input_with_kwargs(indata, kwargs)
        try:
            if indata and session.get("set_project"):
                raise EngineException(
                    "Cannot edit content and set to project (query string SET_PROJECT) at same time",
                    HTTPStatus.UNPROCESSABLE_ENTITY,
                )
            # TODO self._check_edition(session, indata, _id, force)
            if not content:
                content = self.show(session, _id)

            for okas in indata["oka"]:
                if not okas["_id"]:
                    okas.pop("_id")
                if not okas["sw_catalog_path"]:
                    okas.pop("sw_catalog_path")

            indata = self._validate_input_edit(indata, content, force=session["force"])

            # To allow project addressing by name AS WELL AS _id. Get the _id, just in case the provided one is a name
            _id = content.get("_id") or _id

            content = self.check_conflict_on_edit(session, content, indata, _id=_id)
            op_id = self.format_on_edit(content, indata)
            self.db.replace(self.topic, _id, content)
            return op_id
        except ValidationError as e:
            raise EngineException(e, HTTPStatus.UNPROCESSABLE_ENTITY)

    def delete_ksu(self, session, _id, indata, dry_run=False, not_send_msg=None):
        _id_list = []
        if _id == "delete":
            for ksus in indata["ksus"]:
                content = ksus
                _id = content["_id"]
                content.pop("_id")
                op_id, not_send_msg_ksu = self.delete(session, _id)
                if not not_send_msg_ksu:
                    _id_list.append(_id)
        else:
            op_id, not_send_msg_ksu = self.delete(session, _id)
            if not not_send_msg_ksu:
                _id_list.append(_id)

        if _id_list:
            data = {
                "ksus_list": _id_list,
                "operation_id": op_id,
                "force": session["force"],
            }
            self._send_msg("delete", data, not_send_msg)
        return op_id

    def delete(self, session, _id):
        if not self.multiproject:
            filter_q = {}
        else:
            filter_q = self._get_project_filter(session)
        filter_q[self.id_field(self.topic, _id)] = _id
        item_content = self.db.get_one(self.topic, filter_q)
        item_content["state"] = "IN_DELETION"
        item_content["operatingState"] = "PROCESSING"
        item_content["resourceState"] = "IN_PROGRESS"
        op_id = self.format_on_operation(
            item_content,
            "delete",
            None,
        )
        self.db.set_one(self.topic, {"_id": item_content["_id"]}, item_content)

        if item_content["oka"][0].get("_id"):
            used_oka = {}
            existing_oka = []
            for okas in item_content["oka"]:
                used_oka["_id"] = okas["_id"]

            filter = self._get_project_filter(session)
            data = self.db.get_list(self.topic, filter)

            if data:
                for ksus in data:
                    if ksus["_id"] != _id:
                        for okas in ksus["oka"]:
                            self.logger.info("OKA: {}".format(okas))
                            if okas.get("sw_catalog_path", ""):
                                continue
                            elif okas["_id"] not in existing_oka:
                                existing_oka.append(okas["_id"])

            if used_oka:
                for oka, oka_id in used_oka.items():
                    if oka_id not in existing_oka:
                        self.db.set_one(
                            self.okapkg_topic,
                            {"_id": oka_id},
                            {"_admin.usageState": "NOT_IN_USE"},
                        )
        # Check if the profile exists. If it doesn't, no message should be sent to Kafka
        not_send_msg = None
        profile_id = item_content["profile"]["_id"]
        profile_type = item_content["profile"]["profile_type"]
        profile_collection_map = {
            "app_profiles": "k8sapp",
            "resource_profiles": "k8sresource",
            "infra_controller_profiles": "k8sinfra_controller",
            "infra_config_profiles": "k8sinfra_config",
        }
        profile_collection = profile_collection_map[profile_type]
        profile_content = self.db.get_one(
            profile_collection, {"_id": profile_id}, fail_on_empty=False
        )
        if not profile_content:
            self.db.del_one(self.topic, filter_q)
            not_send_msg = True
        return op_id, not_send_msg


class OkaTopic(DescriptorTopic, ACMOperationTopic):
    topic = "okas"
    topic_msg = "oka"
    schema_new = oka_schema
    schema_edit = oka_schema

    def __init__(self, db, fs, msg, auth):
        super().__init__(db, fs, msg, auth)
        self.logger = logging.getLogger("nbi.oka")

    @staticmethod
    def format_on_new(content, project_id=None, make_public=False):
        DescriptorTopic.format_on_new(
            content, project_id=project_id, make_public=make_public
        )
        content["current_operation"] = None
        content["state"] = "PENDING_CONTENT"
        content["operatingState"] = "PROCESSING"
        content["resourceState"] = "IN_PROGRESS"

    def check_conflict_on_del(self, session, _id, db_content):
        usage_state = db_content["_admin"]["usageState"]
        if usage_state == "IN_USE":
            raise EngineException(
                "There is a KSU using this package",
                http_code=HTTPStatus.CONFLICT,
            )

    def check_conflict_on_edit(self, session, final_content, edit_content, _id):
        if "name" in edit_content:
            if final_content["name"] == edit_content["name"]:
                name = edit_content["name"]
                raise EngineException(
                    f"No update, new name for the OKA is the same: {name}",
                    http_code=HTTPStatus.CONFLICT,
                )
            else:
                self.check_unique_name(session, edit_content["name"])
        elif (
            "description" in edit_content
            and final_content["description"] == edit_content["description"]
        ):
            description = edit_content["description"]
            raise EngineException(
                f"No update, new description for the OKA is the same: {description}",
                http_code=HTTPStatus.CONFLICT,
            )
        return final_content

    def edit(self, session, _id, indata=None, kwargs=None, content=None):
        indata = self._remove_envelop(indata)

        # Override descriptor with query string kwargs
        if kwargs:
            self._update_input_with_kwargs(indata, kwargs)
        try:
            if indata and session.get("set_project"):
                raise EngineException(
                    "Cannot edit content and set to project (query string SET_PROJECT) at same time",
                    HTTPStatus.UNPROCESSABLE_ENTITY,
                )
            # TODO self._check_edition(session, indata, _id, force)
            if not content:
                content = self.show(session, _id)

            indata = self._validate_input_edit(indata, content, force=session["force"])

            # To allow project addressing by name AS WELL AS _id. Get the _id, just in case the provided one is a name
            _id = content.get("_id") or _id

            content = self.check_conflict_on_edit(session, content, indata, _id=_id)
            op_id = self.format_on_edit(content, indata)
            deep_update_rfc7396(content, indata)

            self.db.replace(self.topic, _id, content)
            return op_id
        except ValidationError as e:
            raise EngineException(e, HTTPStatus.UNPROCESSABLE_ENTITY)

    def delete(self, session, _id, dry_run=False, not_send_msg=None):
        if not self.multiproject:
            filter_q = {}
        else:
            filter_q = self._get_project_filter(session)
        filter_q[self.id_field(self.topic, _id)] = _id
        item_content = self.db.get_one(self.topic, filter_q)
        item_content["state"] = "IN_DELETION"
        item_content["operatingState"] = "PROCESSING"
        self.check_conflict_on_del(session, _id, item_content)
        op_id = self.format_on_operation(
            item_content,
            "delete",
            None,
        )
        self.db.set_one(self.topic, {"_id": item_content["_id"]}, item_content)
        self._send_msg(
            "delete",
            {"oka_id": _id, "operation_id": op_id, "force": session["force"]},
            not_send_msg=not_send_msg,
        )
        return op_id

    def new(self, rollback, session, indata=None, kwargs=None, headers=None):
        # _remove_envelop
        if indata:
            if "userDefinedData" in indata:
                indata = indata["userDefinedData"]

        content = {"_admin": {"userDefinedData": indata, "revision": 0}}

        self._update_input_with_kwargs(content, kwargs)
        content = BaseTopic._validate_input_new(
            self, input=kwargs, force=session["force"]
        )

        self.check_unique_name(session, content["name"])
        operation_params = {}
        for content_key, content_value in content.items():
            operation_params[content_key] = content_value
        self.format_on_new(
            content, session["project_id"], make_public=session["public"]
        )
        op_id = self.format_on_operation(
            content,
            operation_type="create",
            operation_params=operation_params,
        )
        content["git_name"] = self.create_gitname(content, session)
        _id = self.db.create(self.topic, content)
        rollback.append({"topic": self.topic, "_id": _id})
        return _id, op_id

    def upload_content(self, session, _id, indata, kwargs, headers):
        current_desc = self.show(session, _id)

        compressed = None
        content_type = headers.get("Content-Type")
        if (
            content_type
            and "application/gzip" in content_type
            or "application/x-gzip" in content_type
        ):
            compressed = "gzip"
        if content_type and "application/zip" in content_type:
            compressed = "zip"
        filename = headers.get("Content-Filename")
        if not filename and compressed:
            filename = "package.tar.gz" if compressed == "gzip" else "package.zip"
        elif not filename:
            filename = "package"

        revision = 1
        if "revision" in current_desc["_admin"]:
            revision = current_desc["_admin"]["revision"] + 1

        file_pkg = None
        fs_rollback = []

        try:
            start = 0
            # Rather than using a temp folder, we will store the package in a folder based on
            # the current revision.
            proposed_revision_path = _id + ":" + str(revision)
            # all the content is upload here and if ok, it is rename from id_ to is folder

            if start:
                if not self.fs.file_exists(proposed_revision_path, "dir"):
                    raise EngineException(
                        "invalid Transaction-Id header", HTTPStatus.NOT_FOUND
                    )
            else:
                self.fs.file_delete(proposed_revision_path, ignore_non_exist=True)
                self.fs.mkdir(proposed_revision_path)
                fs_rollback.append(proposed_revision_path)

            storage = self.fs.get_params()
            storage["folder"] = proposed_revision_path
            storage["zipfile"] = filename

            file_path = (proposed_revision_path, filename)
            file_pkg = self.fs.file_open(file_path, "a+b")

            if isinstance(indata, dict):
                indata_text = yaml.safe_dump(indata, indent=4, default_flow_style=False)
                file_pkg.write(indata_text.encode(encoding="utf-8"))
            else:
                indata_len = 0
                indata = indata.file
                while True:
                    indata_text = indata.read(4096)
                    indata_len += len(indata_text)
                    if not indata_text:
                        break
                    file_pkg.write(indata_text)

            # Need to close the file package here so it can be copied from the
            # revision to the current, unrevisioned record
            if file_pkg:
                file_pkg.close()
            file_pkg = None

            # Fetch both the incoming, proposed revision and the original revision so we
            # can call a validate method to compare them
            current_revision_path = _id + "/"
            self.fs.sync(from_path=current_revision_path)
            self.fs.sync(from_path=proposed_revision_path)

            # Is this required?
            if revision > 1:
                try:
                    self._validate_descriptor_changes(
                        _id,
                        filename,
                        current_revision_path,
                        proposed_revision_path,
                    )
                except Exception as e:
                    shutil.rmtree(
                        self.fs.path + current_revision_path, ignore_errors=True
                    )
                    shutil.rmtree(
                        self.fs.path + proposed_revision_path, ignore_errors=True
                    )
                    # Only delete the new revision.  We need to keep the original version in place
                    # as it has not been changed.
                    self.fs.file_delete(proposed_revision_path, ignore_non_exist=True)
                    raise e

            indata = self._remove_envelop(indata)

            # Override descriptor with query string kwargs
            if kwargs:
                self._update_input_with_kwargs(indata, kwargs)

            current_desc["_admin"]["storage"] = storage
            current_desc["_admin"]["onboardingState"] = "ONBOARDED"
            current_desc["_admin"]["operationalState"] = "ENABLED"
            current_desc["_admin"]["modified"] = time()
            current_desc["_admin"]["revision"] = revision

            deep_update_rfc7396(current_desc, indata)

            # Copy the revision to the active package name by its original id
            shutil.rmtree(self.fs.path + current_revision_path, ignore_errors=True)
            os.rename(
                self.fs.path + proposed_revision_path,
                self.fs.path + current_revision_path,
            )
            self.fs.file_delete(current_revision_path, ignore_non_exist=True)
            self.fs.mkdir(current_revision_path)
            self.fs.reverse_sync(from_path=current_revision_path)

            shutil.rmtree(self.fs.path + _id)
            kwargs = {}
            kwargs["package"] = filename
            if headers["Method"] == "POST":
                current_desc["state"] = "IN_CREATION"
                op_id = current_desc.get("operationHistory", [{"op_id": None}])[-1].get(
                    "op_id"
                )
            elif headers["Method"] in ("PUT", "PATCH"):
                op_id = self.format_on_operation(
                    current_desc,
                    "update",
                    kwargs,
                )
                current_desc["operatingState"] = "PROCESSING"
                current_desc["resourceState"] = "IN_PROGRESS"

            self.db.replace(self.topic, _id, current_desc)

            #  Store a copy of the package as a point in time revision
            revision_desc = dict(current_desc)
            revision_desc["_id"] = _id + ":" + str(revision_desc["_admin"]["revision"])
            self.db.create(self.topic + "_revisions", revision_desc)
            fs_rollback = []

            if headers["Method"] == "POST":
                self._send_msg("create", {"oka_id": _id, "operation_id": op_id})
            elif headers["Method"] == "PUT" or "PATCH":
                self._send_msg("edit", {"oka_id": _id, "operation_id": op_id})

            return True

        except EngineException:
            raise
        finally:
            if file_pkg:
                file_pkg.close()
            for file in fs_rollback:
                self.fs.file_delete(file, ignore_non_exist=True)
