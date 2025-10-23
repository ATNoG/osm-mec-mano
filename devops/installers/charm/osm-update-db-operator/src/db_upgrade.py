# Copyright 2022 Canonical Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

"""Upgrade DB charm module."""

import json
import logging

from pymongo import MongoClient
from uuid import uuid4

logger = logging.getLogger(__name__)


class MongoUpgrade1214:
    """Upgrade MongoDB Database from OSM v12 to v14."""

    @staticmethod
    def gather_vnfr_healing_alerts(vnfr, vnfd):
        alerts = []
        nsr_id = vnfr["nsr-id-ref"]
        df = vnfd.get("df", [{}])[0]
        # Checking for auto-healing configuration
        if "healing-aspect" in df:
            healing_aspects = df["healing-aspect"]
            for healing in healing_aspects:
                for healing_policy in healing.get("healing-policy", ()):
                    vdu_id = healing_policy["vdu-id"]
                    vdur = next(
                        (
                            vdur
                            for vdur in vnfr["vdur"]
                            if vdu_id == vdur["vdu-id-ref"]
                        ),
                        {},
                    )
                    if not vdur:
                        continue
                    metric_name = "vm_status"
                    vdu_name = vdur.get("name")
                    vnf_member_index = vnfr["member-vnf-index-ref"]
                    uuid = str(uuid4())
                    name = f"healing_{uuid}"
                    action = healing_policy
                    # action_on_recovery = healing.get("action-on-recovery")
                    # cooldown_time = healing.get("cooldown-time")
                    # day1 = healing.get("day1")
                    alert = {
                        "uuid": uuid,
                        "name": name,
                        "metric": metric_name,
                        "tags": {
                            "ns_id": nsr_id,
                            "vnf_member_index": vnf_member_index,
                            "vdu_name": vdu_name,
                        },
                        "alarm_status": "ok",
                        "action_type": "healing",
                        "action": action,
                    }
                    alerts.append(alert)
        return alerts

    @staticmethod
    def gather_vnfr_scaling_alerts(vnfr, vnfd):
        alerts = []
        nsr_id = vnfr["nsr-id-ref"]
        df = vnfd.get("df", [{}])[0]
        # Checking for auto-scaling configuration
        if "scaling-aspect" in df:
            rel_operation_types = {
                "GE": ">=",
                "LE": "<=",
                "GT": ">",
                "LT": "<",
                "EQ": "==",
                "NE": "!=",
            }
            scaling_aspects = df["scaling-aspect"]
            all_vnfd_monitoring_params = {}
            for ivld in vnfd.get("int-virtual-link-desc", ()):
                for mp in ivld.get("monitoring-parameters", ()):
                    all_vnfd_monitoring_params[mp.get("id")] = mp
            for vdu in vnfd.get("vdu", ()):
                for mp in vdu.get("monitoring-parameter", ()):
                    all_vnfd_monitoring_params[mp.get("id")] = mp
            for df in vnfd.get("df", ()):
                for mp in df.get("monitoring-parameter", ()):
                    all_vnfd_monitoring_params[mp.get("id")] = mp
            for scaling_aspect in scaling_aspects:
                scaling_group_name = scaling_aspect.get("name", "")
                # Get monitored VDUs
                all_monitored_vdus = set()
                for delta in scaling_aspect.get(
                    "aspect-delta-details", {}
                ).get("deltas", ()):
                    for vdu_delta in delta.get("vdu-delta", ()):
                        all_monitored_vdus.add(vdu_delta.get("id"))
                monitored_vdurs = list(
                    filter(
                        lambda vdur: vdur["vdu-id-ref"]
                        in all_monitored_vdus,
                        vnfr["vdur"],
                    )
                )
                if not monitored_vdurs:
                    logger.error("Scaling criteria is referring to a vnf-monitoring-param that does not contain a reference to a vdu or vnf metric")
                    continue
                for scaling_policy in scaling_aspect.get(
                    "scaling-policy", ()
                ):
                    if scaling_policy["scaling-type"] != "automatic":
                        continue
                    threshold_time = scaling_policy.get(
                        "threshold-time", "1"
                    )
                    cooldown_time = scaling_policy.get("cooldown-time", "0")
                    for scaling_criteria in scaling_policy["scaling-criteria"]:
                        monitoring_param_ref = scaling_criteria.get(
                            "vnf-monitoring-param-ref"
                        )
                        vnf_monitoring_param = all_vnfd_monitoring_params[
                            monitoring_param_ref
                        ]
                        for vdur in monitored_vdurs:
                            vdu_id = vdur["vdu-id-ref"]
                            metric_name = vnf_monitoring_param.get("performance-metric")
                            metric_name = f"osm_{metric_name}"
                            vdu_name = vdur["name"]
                            vnf_member_index = vnfr["member-vnf-index-ref"]
                            scalein_threshold = scaling_criteria.get("scale-in-threshold")
                            # Looking for min/max-number-of-instances
                            instances_min_number = 1
                            instances_max_number = 1
                            vdu_profile = df["vdu-profile"]
                            if vdu_profile:
                                profile = next(
                                    item
                                    for item in vdu_profile
                                    if item["id"] == vdu_id
                                )
                                instances_min_number = profile.get("min-number-of-instances", 1)
                                instances_max_number = profile.get("max-number-of-instances", 1)

                            if scalein_threshold:
                                uuid = str(uuid4())
                                name = f"scalein_{uuid}"
                                operation = scaling_criteria["scale-in-relational-operation"]
                                rel_operator = rel_operation_types.get(operation, "<=")
                                metric_selector = f'{metric_name}{{ns_id="{nsr_id}", vnf_member_index="{vnf_member_index}", vdu_id="{vdu_id}"}}'
                                expression = f"(count ({metric_selector}) > {instances_min_number}) and (avg({metric_selector}) {rel_operator} {scalein_threshold})"
                                labels = {
                                    "ns_id": nsr_id,
                                    "vnf_member_index": vnf_member_index,
                                    "vdu_id": vdu_id,
                                }
                                prom_cfg = {
                                    "alert": name,
                                    "expr": expression,
                                    "for": str(threshold_time) + "m",
                                    "labels": labels,
                                }
                                action = scaling_policy
                                action = {
                                    "scaling-group": scaling_group_name,
                                    "cooldown-time": cooldown_time,
                                }
                                alert = {
                                    "uuid": uuid,
                                    "name": name,
                                    "metric": metric_name,
                                    "tags": {
                                        "ns_id": nsr_id,
                                        "vnf_member_index": vnf_member_index,
                                        "vdu_id": vdu_id,
                                    },
                                    "alarm_status": "ok",
                                    "action_type": "scale_in",
                                    "action": action,
                                    "prometheus_config": prom_cfg,
                                }
                                alerts.append(alert)

                            scaleout_threshold = scaling_criteria.get("scale-out-threshold")
                            if scaleout_threshold:
                                uuid = str(uuid4())
                                name = f"scaleout_{uuid}"
                                operation = scaling_criteria["scale-out-relational-operation"]
                                rel_operator = rel_operation_types.get(operation, "<=")
                                metric_selector = f'{metric_name}{{ns_id="{nsr_id}", vnf_member_index="{vnf_member_index}", vdu_id="{vdu_id}"}}'
                                expression = f"(count ({metric_selector}) < {instances_max_number}) and (avg({metric_selector}) {rel_operator} {scaleout_threshold})"
                                labels = {
                                    "ns_id": nsr_id,
                                    "vnf_member_index": vnf_member_index,
                                    "vdu_id": vdu_id,
                                }
                                prom_cfg = {
                                    "alert": name,
                                    "expr": expression,
                                    "for": str(threshold_time) + "m",
                                    "labels": labels,
                                }
                                action = scaling_policy
                                action = {
                                    "scaling-group": scaling_group_name,
                                    "cooldown-time": cooldown_time,
                                }
                                alert = {
                                    "uuid": uuid,
                                    "name": name,
                                    "metric": metric_name,
                                    "tags": {
                                        "ns_id": nsr_id,
                                        "vnf_member_index": vnf_member_index,
                                        "vdu_id": vdu_id,
                                    },
                                    "alarm_status": "ok",
                                    "action_type": "scale_out",
                                    "action": action,
                                    "prometheus_config": prom_cfg,
                                }
                                alerts.append(alert)
        return alerts

    @staticmethod
    def _migrate_alerts(osm_db):
        """Create new alerts collection.
        """
        if "alerts" in osm_db.list_collection_names():
            return
        logger.info("Entering in MongoUpgrade1214._migrate_alerts function")

        # Get vnfds from MongoDB
        logger.info("Reading VNF descriptors:")
        vnfds = osm_db["vnfds"]
        db_vnfds = []
        for vnfd in vnfds.find():
            logger.info(f'  {vnfd["_id"]}: {vnfd["description"]}')
            db_vnfds.append(vnfd)

        # Get vnfrs from MongoDB
        logger.info("Reading VNFRs")
        vnfrs = osm_db["vnfrs"]

        # Gather healing and scaling alerts for each vnfr
        healing_alerts = []
        scaling_alerts = []
        for vnfr in vnfrs.find():
            logger.info(f'  vnfr {vnfr["_id"]}')
            vnfd = next((sub for sub in db_vnfds if sub["_id"] == vnfr["vnfd-id"]), None)
            healing_alerts.extend(MongoUpgrade1214.gather_vnfr_healing_alerts(vnfr, vnfd))
            scaling_alerts.extend(MongoUpgrade1214.gather_vnfr_scaling_alerts(vnfr, vnfd))

        # Add new alerts in MongoDB
        alerts = osm_db["alerts"]
        for alert in healing_alerts:
            logger.info(f"Storing healing alert in MongoDB: {alert}")
            alerts.insert_one(alert)
        for alert in scaling_alerts:
            logger.info(f"Storing scaling alert in MongoDB: {alert}")
            alerts.insert_one(alert)

        # Delete old alarms collections
        logger.info("Deleting alarms and alarms_action collections")
        alarms = osm_db["alarms"]
        alarms.drop()
        alarms_action = osm_db["alarms_action"]
        alarms_action.drop()


    @staticmethod
    def upgrade(mongo_uri):
        """Upgrade alerts in MongoDB."""
        logger.info("Entering in MongoUpgrade1214.upgrade function")
        myclient = MongoClient(mongo_uri)
        osm_db = myclient["osm"]
        MongoUpgrade1214._migrate_alerts(osm_db)


class MongoUpgrade1012:
    """Upgrade MongoDB Database from OSM v10 to v12."""

    @staticmethod
    def _remove_namespace_from_k8s(nsrs, nsr):
        namespace = "kube-system:"
        if nsr["_admin"].get("deployed"):
            k8s_list = []
            for k8s in nsr["_admin"]["deployed"].get("K8s"):
                if k8s.get("k8scluster-uuid"):
                    k8s["k8scluster-uuid"] = k8s["k8scluster-uuid"].replace(namespace, "", 1)
                k8s_list.append(k8s)
            myquery = {"_id": nsr["_id"]}
            nsrs.update_one(myquery, {"$set": {"_admin.deployed.K8s": k8s_list}})

    @staticmethod
    def _update_nsr(osm_db):
        """Update nsr.

        Add vim_message = None if it does not exist.
        Remove "namespace:" from k8scluster-uuid.
        """
        if "nsrs" not in osm_db.list_collection_names():
            return
        logger.info("Entering in MongoUpgrade1012._update_nsr function")

        nsrs = osm_db["nsrs"]
        for nsr in nsrs.find():
            logger.debug(f"Updating {nsr['_id']} nsr")
            for key, values in nsr.items():
                if isinstance(values, list):
                    item_list = []
                    for value in values:
                        if isinstance(value, dict) and value.get("vim_info"):
                            index = list(value["vim_info"].keys())[0]
                            if not value["vim_info"][index].get("vim_message"):
                                value["vim_info"][index]["vim_message"] = None
                            item_list.append(value)
                    myquery = {"_id": nsr["_id"]}
                    nsrs.update_one(myquery, {"$set": {key: item_list}})
            MongoUpgrade1012._remove_namespace_from_k8s(nsrs, nsr)

    @staticmethod
    def _update_vnfr(osm_db):
        """Update vnfr.

        Add vim_message to vdur if it does not exist.
        Copy content of interfaces into interfaces_backup.
        """
        if "vnfrs" not in osm_db.list_collection_names():
            return
        logger.info("Entering in MongoUpgrade1012._update_vnfr function")
        mycol = osm_db["vnfrs"]
        for vnfr in mycol.find():
            logger.debug(f"Updating {vnfr['_id']} vnfr")
            vdur_list = []
            for vdur in vnfr["vdur"]:
                if vdur.get("vim_info"):
                    index = list(vdur["vim_info"].keys())[0]
                    if not vdur["vim_info"][index].get("vim_message"):
                        vdur["vim_info"][index]["vim_message"] = None
                    if vdur["vim_info"][index].get(
                        "interfaces", "Not found"
                    ) != "Not found" and not vdur["vim_info"][index].get("interfaces_backup"):
                        vdur["vim_info"][index]["interfaces_backup"] = vdur["vim_info"][index][
                            "interfaces"
                        ]
                vdur_list.append(vdur)
            myquery = {"_id": vnfr["_id"]}
            mycol.update_one(myquery, {"$set": {"vdur": vdur_list}})

    @staticmethod
    def _update_k8scluster(osm_db):
        """Remove namespace from helm-chart and helm-chart-v3 id."""
        if "k8sclusters" not in osm_db.list_collection_names():
            return
        logger.info("Entering in MongoUpgrade1012._update_k8scluster function")
        namespace = "kube-system:"
        k8sclusters = osm_db["k8sclusters"]
        for k8scluster in k8sclusters.find():
            if k8scluster["_admin"].get("helm-chart") and k8scluster["_admin"]["helm-chart"].get(
                "id"
            ):
                if k8scluster["_admin"]["helm-chart"]["id"].startswith(namespace):
                    k8scluster["_admin"]["helm-chart"]["id"] = k8scluster["_admin"]["helm-chart"][
                        "id"
                    ].replace(namespace, "", 1)
            if k8scluster["_admin"].get("helm-chart-v3") and k8scluster["_admin"][
                "helm-chart-v3"
            ].get("id"):
                if k8scluster["_admin"]["helm-chart-v3"]["id"].startswith(namespace):
                    k8scluster["_admin"]["helm-chart-v3"]["id"] = k8scluster["_admin"][
                        "helm-chart-v3"
                    ]["id"].replace(namespace, "", 1)
            myquery = {"_id": k8scluster["_id"]}
            k8sclusters.update_one(myquery, {"$set": k8scluster})

    @staticmethod
    def upgrade(mongo_uri):
        """Upgrade nsr, vnfr and k8scluster in DB."""
        logger.info("Entering in MongoUpgrade1012.upgrade function")
        myclient = MongoClient(mongo_uri)
        osm_db = myclient["osm"]
        MongoUpgrade1012._update_nsr(osm_db)
        MongoUpgrade1012._update_vnfr(osm_db)
        MongoUpgrade1012._update_k8scluster(osm_db)


class MongoUpgrade910:
    """Upgrade MongoDB Database from OSM v9 to v10."""

    @staticmethod
    def upgrade(mongo_uri):
        """Add parameter alarm status = OK if not found in alarms collection."""
        myclient = MongoClient(mongo_uri)
        osm_db = myclient["osm"]
        collist = osm_db.list_collection_names()

        if "alarms" in collist:
            mycol = osm_db["alarms"]
            for x in mycol.find():
                if not x.get("alarm_status"):
                    myquery = {"_id": x["_id"]}
                    mycol.update_one(myquery, {"$set": {"alarm_status": "ok"}})


class MongoPatch1837:
    """Patch Bug 1837 on MongoDB."""

    @staticmethod
    def _update_nslcmops_params(osm_db):
        """Updates the nslcmops collection to change the additional params to a string."""
        logger.info("Entering in MongoPatch1837._update_nslcmops_params function")
        if "nslcmops" in osm_db.list_collection_names():
            nslcmops = osm_db["nslcmops"]
            for nslcmop in nslcmops.find():
                if nslcmop.get("operationParams"):
                    if nslcmop["operationParams"].get("additionalParamsForVnf") and isinstance(
                        nslcmop["operationParams"].get("additionalParamsForVnf"), list
                    ):
                        string_param = json.dumps(
                            nslcmop["operationParams"]["additionalParamsForVnf"]
                        )
                        myquery = {"_id": nslcmop["_id"]}
                        nslcmops.update_one(
                            myquery,
                            {
                                "$set": {
                                    "operationParams": {"additionalParamsForVnf": string_param}
                                }
                            },
                        )
                    elif nslcmop["operationParams"].get("primitive_params") and isinstance(
                        nslcmop["operationParams"].get("primitive_params"), dict
                    ):
                        string_param = json.dumps(nslcmop["operationParams"]["primitive_params"])
                        myquery = {"_id": nslcmop["_id"]}
                        nslcmops.update_one(
                            myquery,
                            {"$set": {"operationParams": {"primitive_params": string_param}}},
                        )

    @staticmethod
    def _update_vnfrs_params(osm_db):
        """Updates the vnfrs collection to change the additional params to a string."""
        logger.info("Entering in MongoPatch1837._update_vnfrs_params function")
        if "vnfrs" in osm_db.list_collection_names():
            mycol = osm_db["vnfrs"]
            for vnfr in mycol.find():
                if vnfr.get("kdur"):
                    kdur_list = []
                    for kdur in vnfr["kdur"]:
                        if kdur.get("additionalParams") and not isinstance(
                            kdur["additionalParams"], str
                        ):
                            kdur["additionalParams"] = json.dumps(kdur["additionalParams"])
                        kdur_list.append(kdur)
                    myquery = {"_id": vnfr["_id"]}
                    mycol.update_one(
                        myquery,
                        {"$set": {"kdur": kdur_list}},
                    )
                    vnfr["kdur"] = kdur_list

    @staticmethod
    def patch(mongo_uri):
        """Updates the database to change the additional params from dict to a string."""
        logger.info("Entering in MongoPatch1837.patch function")
        myclient = MongoClient(mongo_uri)
        osm_db = myclient["osm"]
        MongoPatch1837._update_nslcmops_params(osm_db)
        MongoPatch1837._update_vnfrs_params(osm_db)


MONGODB_UPGRADE_FUNCTIONS = {
    "9": {"10": [MongoUpgrade910.upgrade]},
    "10": {"12": [MongoUpgrade1012.upgrade]},
    "12": {"14": [MongoUpgrade1214.upgrade]},
}
MYSQL_UPGRADE_FUNCTIONS = {}
BUG_FIXES = {
    1837: MongoPatch1837.patch,
}


class MongoUpgrade:
    """Upgrade MongoDB Database."""

    def __init__(self, mongo_uri):
        self.mongo_uri = mongo_uri

    def upgrade(self, current, target):
        """Validates the upgrading path and upgrades the DB."""
        self._validate_upgrade(current, target)
        for function in MONGODB_UPGRADE_FUNCTIONS.get(current)[target]:
            function(self.mongo_uri)

    def _validate_upgrade(self, current, target):
        """Check if the upgrade path chosen is possible."""
        logger.info("Validating the upgrade path")
        if current not in MONGODB_UPGRADE_FUNCTIONS:
            raise Exception(f"cannot upgrade from {current} version.")
        if target not in MONGODB_UPGRADE_FUNCTIONS[current]:
            raise Exception(f"cannot upgrade from version {current} to {target}.")

    def apply_patch(self, bug_number: int) -> None:
        """Checks the bug-number and applies the fix in the database."""
        if bug_number not in BUG_FIXES:
            raise Exception(f"There is no patch for bug {bug_number}")
        patch_function = BUG_FIXES[bug_number]
        patch_function(self.mongo_uri)


class MysqlUpgrade:
    """Upgrade Mysql Database."""

    def __init__(self, mysql_uri):
        self.mysql_uri = mysql_uri

    def upgrade(self, current, target):
        """Validates the upgrading path and upgrades the DB."""
        self._validate_upgrade(current, target)
        for function in MYSQL_UPGRADE_FUNCTIONS[current][target]:
            function(self.mysql_uri)

    def _validate_upgrade(self, current, target):
        """Check if the upgrade path chosen is possible."""
        logger.info("Validating the upgrade path")
        if current not in MYSQL_UPGRADE_FUNCTIONS:
            raise Exception(f"cannot upgrade from {current} version.")
        if target not in MYSQL_UPGRADE_FUNCTIONS[current]:
            raise Exception(f"cannot upgrade from version {current} to {target}.")
