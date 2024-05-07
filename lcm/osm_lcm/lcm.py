#!/usr/bin/python3
# -*- coding: utf-8 -*-

##
# Copyright 2018 Telefonica S.A.
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
##


# DEBUG WITH PDB
import pdb

import asyncio
import yaml
import logging
import logging.handlers
import getopt
import sys
from random import SystemRandom

from osm_lcm import ns, vim_sdn, netslice
from osm_lcm.ng_ro import NgRoException, NgRoClient
from osm_lcm.ROclient import ROClient, ROClientException

from time import time
from osm_lcm.lcm_utils import versiontuple, LcmException, TaskRegistry, LcmExceptionExit
from osm_lcm import version as lcm_version, version_date as lcm_version_date

from osm_common import msglocal, msgkafka
from osm_common import version as common_version
from osm_common.dbbase import DbException
from osm_common.fsbase import FsException
from osm_common.msgbase import MsgException
from osm_lcm.data_utils.database.database import Database
from osm_lcm.data_utils.filesystem.filesystem import Filesystem
from osm_lcm.data_utils.lcm_config import LcmCfg
from osm_lcm.lcm_hc import get_health_check_file
from os import path, getenv
from n2vc import version as n2vc_version
import traceback

if getenv("OSMLCM_PDB_DEBUG", None) is not None:
    pdb.set_trace()


__author__ = "Alfonso Tierno"
min_RO_version = "6.0.2"
min_n2vc_version = "0.0.2"

min_common_version = "0.1.19"


class Lcm:
    ping_interval_pace = (
        120  # how many time ping is send once is confirmed all is running
    )
    ping_interval_boot = 5  # how many time ping is sent when booting

    main_config = LcmCfg()

    def __init__(self, config_file):
        """
        Init, Connect to database, filesystem storage, and messaging
        :param config: two level dictionary with configuration. Top level should contain 'database', 'storage',
        :return: None
        """
        self.db = None
        self.msg = None
        self.msg_admin = None
        self.fs = None
        self.pings_not_received = 1
        self.consecutive_errors = 0
        self.first_start = False

        # logging
        self.logger = logging.getLogger("lcm")
        # get id
        self.worker_id = self.get_process_id()
        # load configuration
        config = self.read_config_file(config_file)
        self.main_config.set_from_dict(config)
        self.main_config.transform()
        self.main_config.load_from_env()
        self.logger.critical("Loaded configuration:" + str(self.main_config.to_dict()))
        # TODO: check if lcm_hc.py is necessary
        self.health_check_file = get_health_check_file(self.main_config.to_dict())
        self.ns = (
            self.netslice
        ) = (
            self.vim
        ) = self.wim = self.sdn = self.k8scluster = self.vca = self.k8srepo = None

        # logging
        log_format_simple = (
            "%(asctime)s %(levelname)s %(name)s %(filename)s:%(lineno)s %(message)s"
        )
        log_formatter_simple = logging.Formatter(
            log_format_simple, datefmt="%Y-%m-%dT%H:%M:%S"
        )
        if self.main_config.globalConfig.logfile:
            file_handler = logging.handlers.RotatingFileHandler(
                self.main_config.globalConfig.logfile,
                maxBytes=100e6,
                backupCount=9,
                delay=0,
            )
            file_handler.setFormatter(log_formatter_simple)
            self.logger.addHandler(file_handler)
        if not self.main_config.globalConfig.to_dict()["nologging"]:
            str_handler = logging.StreamHandler()
            str_handler.setFormatter(log_formatter_simple)
            self.logger.addHandler(str_handler)

        if self.main_config.globalConfig.to_dict()["loglevel"]:
            self.logger.setLevel(self.main_config.globalConfig.loglevel)

        # logging other modules
        for logger in ("message", "database", "storage", "tsdb"):
            logger_config = self.main_config.to_dict()[logger]
            logger_module = logging.getLogger(logger_config["logger_name"])
            if logger_config["logfile"]:
                file_handler = logging.handlers.RotatingFileHandler(
                    logger_config["logfile"], maxBytes=100e6, backupCount=9, delay=0
                )
                file_handler.setFormatter(log_formatter_simple)
                logger_module.addHandler(file_handler)
            if logger_config["loglevel"]:
                logger_module.setLevel(logger_config["loglevel"])
        self.logger.critical(
            "starting osm/lcm version {} {}".format(lcm_version, lcm_version_date)
        )

        # check version of N2VC
        # TODO enhance with int conversion or from distutils.version import LooseVersion
        # or with list(map(int, version.split(".")))
        if versiontuple(n2vc_version) < versiontuple(min_n2vc_version):
            raise LcmException(
                "Not compatible osm/N2VC version '{}'. Needed '{}' or higher".format(
                    n2vc_version, min_n2vc_version
                )
            )
        # check version of common
        if versiontuple(common_version) < versiontuple(min_common_version):
            raise LcmException(
                "Not compatible osm/common version '{}'. Needed '{}' or higher".format(
                    common_version, min_common_version
                )
            )

        try:
            self.db = Database(self.main_config.to_dict()).instance.db

            self.fs = Filesystem(self.main_config.to_dict()).instance.fs
            self.fs.sync()

            # copy message configuration in order to remove 'group_id' for msg_admin
            config_message = self.main_config.message.to_dict()
            config_message["loop"] = asyncio.get_event_loop()
            if config_message["driver"] == "local":
                self.msg = msglocal.MsgLocal()
                self.msg.connect(config_message)
                self.msg_admin = msglocal.MsgLocal()
                config_message.pop("group_id", None)
                self.msg_admin.connect(config_message)
            elif config_message["driver"] == "kafka":
                self.msg = msgkafka.MsgKafka()
                self.msg.connect(config_message)
                self.msg_admin = msgkafka.MsgKafka()
                config_message.pop("group_id", None)
                self.msg_admin.connect(config_message)
            else:
                raise LcmException(
                    "Invalid configuration param '{}' at '[message]':'driver'".format(
                        self.main_config.message.driver
                    )
                )
        except (DbException, FsException, MsgException) as e:
            self.logger.critical(str(e), exc_info=True)
            raise LcmException(str(e))

        # contains created tasks/futures to be able to cancel
        self.lcm_tasks = TaskRegistry(self.worker_id, self.logger)

    async def check_RO_version(self):
        tries = 14
        last_error = None
        while True:
            ro_uri = self.main_config.RO.uri
            if not ro_uri:
                ro_uri = ""
            try:
                # try new  RO, if fail old RO
                try:
                    self.main_config.RO.uri = ro_uri + "ro"
                    ro_server = NgRoClient(**self.main_config.RO.to_dict())
                    ro_version = await ro_server.get_version()
                    self.main_config.RO.ng = True
                except Exception:
                    self.main_config.RO.uri = ro_uri + "openmano"
                    ro_server = ROClient(**self.main_config.RO.to_dict())
                    ro_version = await ro_server.get_version()
                    self.main_config.RO.ng = False
                if versiontuple(ro_version) < versiontuple(min_RO_version):
                    raise LcmException(
                        "Not compatible osm/RO version '{}'. Needed '{}' or higher".format(
                            ro_version, min_RO_version
                        )
                    )
                self.logger.info(
                    "Connected to RO version {} new-generation version {}".format(
                        ro_version, self.main_config.RO.ng
                    )
                )
                return
            except (ROClientException, NgRoException) as e:
                self.main_config.RO.uri = ro_uri
                tries -= 1
                traceback.print_tb(e.__traceback__)
                error_text = "Error while connecting to RO on {}: {}".format(
                    self.main_config.RO.uri, e
                )
                if tries <= 0:
                    self.logger.critical(error_text)
                    raise LcmException(error_text)
                if last_error != error_text:
                    last_error = error_text
                    self.logger.error(
                        error_text + ". Waiting until {} seconds".format(5 * tries)
                    )
                await asyncio.sleep(5)

    async def test(self, param=None):
        self.logger.debug("Starting/Ending test task: {}".format(param))

    async def kafka_ping(self):
        self.logger.debug("Task kafka_ping Enter")
        consecutive_errors = 0
        first_start = True
        kafka_has_received = False
        self.pings_not_received = 1
        while True:
            try:
                await self.msg_admin.aiowrite(
                    "admin",
                    "ping",
                    {
                        "from": "lcm",
                        "to": "lcm",
                        "worker_id": self.worker_id,
                        "version": lcm_version,
                    },
                )
                # time between pings are low when it is not received and at starting
                wait_time = (
                    self.ping_interval_boot
                    if not kafka_has_received
                    else self.ping_interval_pace
                )
                if not self.pings_not_received:
                    kafka_has_received = True
                self.pings_not_received += 1
                await asyncio.sleep(wait_time)
                if self.pings_not_received > 10:
                    raise LcmException("It is not receiving pings from Kafka bus")
                consecutive_errors = 0
                first_start = False
            except LcmException:
                raise
            except Exception as e:
                # if not first_start is the first time after starting. So leave more time and wait
                # to allow kafka starts
                if consecutive_errors == 8 if not first_start else 30:
                    self.logger.error(
                        "Task kafka_read task exit error too many errors. Exception: {}".format(
                            e
                        )
                    )
                    raise
                consecutive_errors += 1
                self.logger.error(
                    "Task kafka_read retrying after Exception {}".format(e)
                )
                wait_time = 2 if not first_start else 5
                await asyncio.sleep(wait_time)

    async def kafka_read_callback(self, topic, command, params):
        order_id = 1

        if topic != "admin" and command != "ping":
            self.logger.debug(
                "Task kafka_read receives {} {}: {}".format(topic, command, params)
            )
        self.consecutive_errors = 0
        self.first_start = False
        order_id += 1
        if command == "exit":
            raise LcmExceptionExit
        elif command.startswith("#"):
            return
        elif command == "echo":
            # just for test
            print(params)
            sys.stdout.flush()
            return
        elif command == "test":
            asyncio.Task(self.test(params))
            return

        if topic == "admin":
            if command == "ping" and params["to"] == "lcm" and params["from"] == "lcm":
                if params.get("worker_id") != self.worker_id:
                    return
                self.pings_not_received = 0
                try:
                    with open(self.health_check_file, "w") as f:
                        f.write(str(time()))
                except Exception as e:
                    self.logger.error(
                        "Cannot write into '{}' for healthcheck: {}".format(
                            self.health_check_file, e
                        )
                    )
            return
        elif topic == "nslcmops":
            if command == "cancel":
                nslcmop_id = params["_id"]
                self.logger.debug("Cancelling nslcmop {}".format(nslcmop_id))
                nsr_id = params["nsInstanceId"]
                # cancel the tasks and wait
                for task in self.lcm_tasks.cancel("ns", nsr_id, nslcmop_id):
                    try:
                        await task
                        self.logger.debug(
                            "Cancelled task ended {},{},{}".format(
                                nsr_id, nslcmop_id, task
                            )
                        )
                    except asyncio.CancelledError:
                        self.logger.debug(
                            "Task already cancelled and finished {},{},{}".format(
                                nsr_id, nslcmop_id, task
                            )
                        )
                # update DB
                q_filter = {"_id": nslcmop_id}
                update_dict = {
                    "operationState": "FAILED_TEMP",
                    "isCancelPending": False,
                }
                unset_dict = {
                    "cancelMode": None,
                }
                self.db.set_one(
                    "nslcmops",
                    q_filter=q_filter,
                    update_dict=update_dict,
                    fail_on_empty=False,
                    unset=unset_dict,
                )
                self.logger.debug("LCM task cancelled {},{}".format(nsr_id, nslcmop_id))
            return
        elif topic == "pla":
            if command == "placement":
                self.ns.update_nsrs_with_pla_result(params)
            return
        elif topic == "k8scluster":
            if command == "create" or command == "created":
                k8scluster_id = params.get("_id")
                task = asyncio.ensure_future(self.k8scluster.create(params, order_id))
                self.lcm_tasks.register(
                    "k8scluster", k8scluster_id, order_id, "k8scluster_create", task
                )
                return
            elif command == "edit" or command == "edited":
                k8scluster_id = params.get("_id")
                task = asyncio.ensure_future(self.k8scluster.edit(params, order_id))
                self.lcm_tasks.register(
                    "k8scluster", k8scluster_id, order_id, "k8scluster_edit", task
                )
                return
            elif command == "delete" or command == "deleted":
                k8scluster_id = params.get("_id")
                task = asyncio.ensure_future(self.k8scluster.delete(params, order_id))
                self.lcm_tasks.register(
                    "k8scluster", k8scluster_id, order_id, "k8scluster_delete", task
                )
                return
        elif topic == "vca":
            if command == "create" or command == "created":
                vca_id = params.get("_id")
                task = asyncio.ensure_future(self.vca.create(params, order_id))
                self.lcm_tasks.register("vca", vca_id, order_id, "vca_create", task)
                return
            elif command == "edit" or command == "edited":
                vca_id = params.get("_id")
                task = asyncio.ensure_future(self.vca.edit(params, order_id))
                self.lcm_tasks.register("vca", vca_id, order_id, "vca_edit", task)
                return
            elif command == "delete" or command == "deleted":
                vca_id = params.get("_id")
                task = asyncio.ensure_future(self.vca.delete(params, order_id))
                self.lcm_tasks.register("vca", vca_id, order_id, "vca_delete", task)
                return
        elif topic == "k8srepo":
            if command == "create" or command == "created":
                k8srepo_id = params.get("_id")
                self.logger.debug("k8srepo_id = {}".format(k8srepo_id))
                task = asyncio.ensure_future(self.k8srepo.create(params, order_id))
                self.lcm_tasks.register(
                    "k8srepo", k8srepo_id, order_id, "k8srepo_create", task
                )
                return
            elif command == "delete" or command == "deleted":
                k8srepo_id = params.get("_id")
                task = asyncio.ensure_future(self.k8srepo.delete(params, order_id))
                self.lcm_tasks.register(
                    "k8srepo", k8srepo_id, order_id, "k8srepo_delete", task
                )
                return
        elif topic == "ns":
            if command == "instantiate":
                # self.logger.debug("Deploying NS {}".format(nsr_id))
                nslcmop = params
                nslcmop_id = nslcmop["_id"]
                nsr_id = nslcmop["nsInstanceId"]
                task = asyncio.ensure_future(self.ns.instantiate(nsr_id, nslcmop_id))
                self.lcm_tasks.register(
                    "ns", nsr_id, nslcmop_id, "ns_instantiate", task
                )
                return
            elif command == "terminate":
                # self.logger.debug("Deleting NS {}".format(nsr_id))
                nslcmop = params
                nslcmop_id = nslcmop["_id"]
                nsr_id = nslcmop["nsInstanceId"]
                self.lcm_tasks.cancel(topic, nsr_id)
                task = asyncio.ensure_future(self.ns.terminate(nsr_id, nslcmop_id))
                self.lcm_tasks.register("ns", nsr_id, nslcmop_id, "ns_terminate", task)
                return
            elif command == "vca_status_refresh":
                nslcmop = params
                nslcmop_id = nslcmop["_id"]
                nsr_id = nslcmop["nsInstanceId"]
                task = asyncio.ensure_future(
                    self.ns.vca_status_refresh(nsr_id, nslcmop_id)
                )
                self.lcm_tasks.register(
                    "ns", nsr_id, nslcmop_id, "ns_vca_status_refresh", task
                )
                return
            elif command == "action":
                # self.logger.debug("Update NS {}".format(nsr_id))
                nslcmop = params
                nslcmop_id = nslcmop["_id"]
                nsr_id = nslcmop["nsInstanceId"]
                task = asyncio.ensure_future(self.ns.action(nsr_id, nslcmop_id))
                self.lcm_tasks.register("ns", nsr_id, nslcmop_id, "ns_action", task)
                return
            elif command == "update":
                # self.logger.debug("Update NS {}".format(nsr_id))
                nslcmop = params
                nslcmop_id = nslcmop["_id"]
                nsr_id = nslcmop["nsInstanceId"]
                task = asyncio.ensure_future(self.ns.update(nsr_id, nslcmop_id))
                self.lcm_tasks.register("ns", nsr_id, nslcmop_id, "ns_update", task)
                return
            elif command == "scale":
                # self.logger.debug("Update NS {}".format(nsr_id))
                nslcmop = params
                nslcmop_id = nslcmop["_id"]
                nsr_id = nslcmop["nsInstanceId"]
                task = asyncio.ensure_future(self.ns.scale(nsr_id, nslcmop_id))
                self.lcm_tasks.register("ns", nsr_id, nslcmop_id, "ns_scale", task)
                return
            elif command == "heal":
                # self.logger.debug("Healing NS {}".format(nsr_id))
                nslcmop = params
                nslcmop_id = nslcmop["_id"]
                nsr_id = nslcmop["nsInstanceId"]
                task = asyncio.ensure_future(self.ns.heal(nsr_id, nslcmop_id))
                self.lcm_tasks.register("ns", nsr_id, nslcmop_id, "ns_heal", task)
                return
            elif command == "migrate":
                nslcmop = params
                nslcmop_id = nslcmop["_id"]
                nsr_id = nslcmop["nsInstanceId"]
                task = asyncio.ensure_future(self.ns.migrate(nsr_id, nslcmop_id))
                self.lcm_tasks.register("ns", nsr_id, nslcmop_id, "ns_migrate", task)
                return
            elif command == "verticalscale":
                nslcmop = params
                nslcmop_id = nslcmop["_id"]
                nsr_id = nslcmop["nsInstanceId"]
                task = asyncio.ensure_future(self.ns.vertical_scale(nsr_id, nslcmop_id))
                self.logger.debug(
                    "nsr_id,nslcmop_id,task {},{},{}".format(nsr_id, nslcmop_id, task)
                )
                self.lcm_tasks.register(
                    "ns", nsr_id, nslcmop_id, "ns_verticalscale", task
                )
                self.logger.debug(
                    "LCM task registered {},{},{} ".format(nsr_id, nslcmop_id, task)
                )
                return
            elif command == "show":
                nsr_id = params
                try:
                    db_nsr = self.db.get_one("nsrs", {"_id": nsr_id})
                    print(
                        "nsr:\n    _id={}\n    operational-status: {}\n    config-status: {}"
                        "\n    detailed-status: {}\n    deploy: {}\n    tasks: {}"
                        "".format(
                            nsr_id,
                            db_nsr["operational-status"],
                            db_nsr["config-status"],
                            db_nsr["detailed-status"],
                            db_nsr["_admin"]["deployed"],
                            self.lcm_tasks.task_registry["ns"].get(nsr_id, ""),
                        )
                    )
                except Exception as e:
                    print("nsr {} not found: {}".format(nsr_id, e))
                sys.stdout.flush()
                return
            elif command == "deleted":
                return  # TODO cleaning of task just in case should be done
            elif command in (
                "vnf_terminated",
                "policy_updated",
                "terminated",
                "instantiated",
                "scaled",
                "healed",
                "actioned",
                "updated",
                "migrated",
                "verticalscaled",
            ):  # "scaled-cooldown-time"
                return

        elif topic == "nsi":  # netslice LCM processes (instantiate, terminate, etc)
            if command == "instantiate":
                # self.logger.debug("Instantiating Network Slice {}".format(nsilcmop["netsliceInstanceId"]))
                nsilcmop = params
                nsilcmop_id = nsilcmop["_id"]  # slice operation id
                nsir_id = nsilcmop["netsliceInstanceId"]  # slice record id
                task = asyncio.ensure_future(
                    self.netslice.instantiate(nsir_id, nsilcmop_id)
                )
                self.lcm_tasks.register(
                    "nsi", nsir_id, nsilcmop_id, "nsi_instantiate", task
                )
                return
            elif command == "terminate":
                # self.logger.debug("Terminating Network Slice NS {}".format(nsilcmop["netsliceInstanceId"]))
                nsilcmop = params
                nsilcmop_id = nsilcmop["_id"]  # slice operation id
                nsir_id = nsilcmop["netsliceInstanceId"]  # slice record id
                self.lcm_tasks.cancel(topic, nsir_id)
                task = asyncio.ensure_future(
                    self.netslice.terminate(nsir_id, nsilcmop_id)
                )
                self.lcm_tasks.register(
                    "nsi", nsir_id, nsilcmop_id, "nsi_terminate", task
                )
                return
            elif command == "show":
                nsir_id = params
                try:
                    db_nsir = self.db.get_one("nsirs", {"_id": nsir_id})
                    print(
                        "nsir:\n    _id={}\n    operational-status: {}\n    config-status: {}"
                        "\n    detailed-status: {}\n    deploy: {}\n    tasks: {}"
                        "".format(
                            nsir_id,
                            db_nsir["operational-status"],
                            db_nsir["config-status"],
                            db_nsir["detailed-status"],
                            db_nsir["_admin"]["deployed"],
                            self.lcm_tasks.task_registry["nsi"].get(nsir_id, ""),
                        )
                    )
                except Exception as e:
                    print("nsir {} not found: {}".format(nsir_id, e))
                sys.stdout.flush()
                return
            elif command == "deleted":
                return  # TODO cleaning of task just in case should be done
            elif command in (
                "terminated",
                "instantiated",
                "scaled",
                "healed",
                "actioned",
            ):  # "scaled-cooldown-time"
                return
        elif topic == "vim_account":
            vim_id = params["_id"]
            if command in ("create", "created"):
                if not self.main_config.RO.ng:
                    task = asyncio.ensure_future(self.vim.create(params, order_id))
                    self.lcm_tasks.register(
                        "vim_account", vim_id, order_id, "vim_create", task
                    )
                return
            elif command == "delete" or command == "deleted":
                self.lcm_tasks.cancel(topic, vim_id)
                task = asyncio.ensure_future(self.vim.delete(params, order_id))
                self.lcm_tasks.register(
                    "vim_account", vim_id, order_id, "vim_delete", task
                )
                return
            elif command == "show":
                print("not implemented show with vim_account")
                sys.stdout.flush()
                return
            elif command in ("edit", "edited"):
                if not self.main_config.RO.ng:
                    task = asyncio.ensure_future(self.vim.edit(params, order_id))
                    self.lcm_tasks.register(
                        "vim_account", vim_id, order_id, "vim_edit", task
                    )
                return
            elif command == "deleted":
                return  # TODO cleaning of task just in case should be done
        elif topic == "wim_account":
            wim_id = params["_id"]
            if command in ("create", "created"):
                if not self.main_config.RO.ng:
                    task = asyncio.ensure_future(self.wim.create(params, order_id))
                    self.lcm_tasks.register(
                        "wim_account", wim_id, order_id, "wim_create", task
                    )
                return
            elif command == "delete" or command == "deleted":
                self.lcm_tasks.cancel(topic, wim_id)
                task = asyncio.ensure_future(self.wim.delete(params, order_id))
                self.lcm_tasks.register(
                    "wim_account", wim_id, order_id, "wim_delete", task
                )
                return
            elif command == "show":
                print("not implemented show with wim_account")
                sys.stdout.flush()
                return
            elif command in ("edit", "edited"):
                task = asyncio.ensure_future(self.wim.edit(params, order_id))
                self.lcm_tasks.register(
                    "wim_account", wim_id, order_id, "wim_edit", task
                )
                return
            elif command == "deleted":
                return  # TODO cleaning of task just in case should be done
        elif topic == "sdn":
            _sdn_id = params["_id"]
            if command in ("create", "created"):
                if not self.main_config.RO.ng:
                    task = asyncio.ensure_future(self.sdn.create(params, order_id))
                    self.lcm_tasks.register(
                        "sdn", _sdn_id, order_id, "sdn_create", task
                    )
                return
            elif command == "delete" or command == "deleted":
                self.lcm_tasks.cancel(topic, _sdn_id)
                task = asyncio.ensure_future(self.sdn.delete(params, order_id))
                self.lcm_tasks.register("sdn", _sdn_id, order_id, "sdn_delete", task)
                return
            elif command in ("edit", "edited"):
                task = asyncio.ensure_future(self.sdn.edit(params, order_id))
                self.lcm_tasks.register("sdn", _sdn_id, order_id, "sdn_edit", task)
                return
            elif command == "deleted":
                return  # TODO cleaning of task just in case should be done
        self.logger.critical("unknown topic {} and command '{}'".format(topic, command))

    async def kafka_read(self):
        self.logger.debug(
            "Task kafka_read Enter with worker_id={}".format(self.worker_id)
        )
        self.consecutive_errors = 0
        self.first_start = True
        while self.consecutive_errors < 10:
            try:
                topics = (
                    "ns",
                    "vim_account",
                    "wim_account",
                    "sdn",
                    "nsi",
                    "k8scluster",
                    "vca",
                    "k8srepo",
                    "pla",
                    "nslcmops",
                )
                topics_admin = ("admin",)
                await asyncio.gather(
                    self.msg.aioread(
                        topics,
                        aiocallback=self.kafka_read_callback,
                        from_beginning=True,
                    ),
                    self.msg_admin.aioread(
                        topics_admin,
                        aiocallback=self.kafka_read_callback,
                        group_id=False,
                    ),
                )

            except LcmExceptionExit:
                self.logger.debug("Bye!")
                break
            except Exception as e:
                # if not first_start is the first time after starting. So leave more time and wait
                # to allow kafka starts
                if self.consecutive_errors == 8 if not self.first_start else 30:
                    self.logger.error(
                        "Task kafka_read task exit error too many errors. Exception: {}".format(
                            e
                        )
                    )
                    raise
                self.consecutive_errors += 1
                self.logger.error(
                    "Task kafka_read retrying after Exception {}".format(e)
                )
                wait_time = 2 if not self.first_start else 5
                await asyncio.sleep(wait_time)

        self.logger.debug("Task kafka_read exit")

    async def kafka_read_ping(self):
        await asyncio.gather(self.kafka_read(), self.kafka_ping())

    async def start(self):
        # check RO version
        await self.check_RO_version()

        self.ns = ns.NsLcm(self.msg, self.lcm_tasks, self.main_config)
        # TODO: modify the rest of classes to use the LcmCfg object instead of dicts
        self.netslice = netslice.NetsliceLcm(
            self.msg, self.lcm_tasks, self.main_config.to_dict(), self.ns
        )
        self.vim = vim_sdn.VimLcm(self.msg, self.lcm_tasks, self.main_config.to_dict())
        self.wim = vim_sdn.WimLcm(self.msg, self.lcm_tasks, self.main_config.to_dict())
        self.sdn = vim_sdn.SdnLcm(self.msg, self.lcm_tasks, self.main_config.to_dict())
        self.k8scluster = vim_sdn.K8sClusterLcm(
            self.msg, self.lcm_tasks, self.main_config.to_dict()
        )
        self.vca = vim_sdn.VcaLcm(self.msg, self.lcm_tasks, self.main_config.to_dict())
        self.k8srepo = vim_sdn.K8sRepoLcm(
            self.msg, self.lcm_tasks, self.main_config.to_dict()
        )

        await self.kafka_read_ping()

        # TODO
        # self.logger.debug("Terminating cancelling creation tasks")
        # self.lcm_tasks.cancel("ALL", "create")
        # timeout = 200
        # while self.is_pending_tasks():
        #     self.logger.debug("Task kafka_read terminating. Waiting for tasks termination")
        #     await asyncio.sleep(2)
        #     timeout -= 2
        #     if not timeout:
        #         self.lcm_tasks.cancel("ALL", "ALL")
        if self.db:
            self.db.db_disconnect()
        if self.msg:
            self.msg.disconnect()
        if self.msg_admin:
            self.msg_admin.disconnect()
        if self.fs:
            self.fs.fs_disconnect()

    def read_config_file(self, config_file):
        try:
            with open(config_file) as f:
                return yaml.safe_load(f)
        except Exception as e:
            self.logger.critical("At config file '{}': {}".format(config_file, e))
            exit(1)

    @staticmethod
    def get_process_id():
        """
        Obtain a unique ID for this process. If running from inside docker, it will get docker ID. If not it
        will provide a random one
        :return: Obtained ID
        """

        def get_docker_id():
            try:
                with open("/proc/self/cgroup", "r") as f:
                    text_id_ = f.readline()
                    _, _, text_id = text_id_.rpartition("/")
                    return text_id.replace("\n", "")[:12]
            except Exception:
                return None

        def generate_random_id():
            return "".join(SystemRandom().choice("0123456789abcdef") for _ in range(12))

        # Try getting docker id. If it fails, generate a random id
        docker_id = get_docker_id()
        return docker_id if docker_id else generate_random_id()


def usage():
    print(
        """Usage: {} [options]
        -c|--config [configuration_file]: loads the configuration file (default: ./lcm.cfg)
        --health-check: do not run lcm, but inspect kafka bus to determine if lcm is healthy
        -h|--help: shows this help
        """.format(
            sys.argv[0]
        )
    )
    # --log-socket-host HOST: send logs to this host")
    # --log-socket-port PORT: send logs using this port (default: 9022)")


if __name__ == "__main__":
    try:
        # print("SYS.PATH='{}'".format(sys.path))
        # load parameters and configuration
        # -h
        # -c value
        # --config value
        # --help
        # --health-check
        opts, args = getopt.getopt(
            sys.argv[1:], "hc:", ["config=", "help", "health-check"]
        )
        # TODO add  "log-socket-host=", "log-socket-port=", "log-file="
        config_file = None
        for o, a in opts:
            if o in ("-h", "--help"):
                usage()
                sys.exit()
            elif o in ("-c", "--config"):
                config_file = a
            elif o == "--health-check":
                from osm_lcm.lcm_hc import health_check

                health_check(config_file, Lcm.ping_interval_pace)
            else:
                print(f"Unhandled option: {o}")
                exit(1)

        if config_file:
            if not path.isfile(config_file):
                print(
                    "configuration file '{}' does not exist".format(config_file),
                    file=sys.stderr,
                )
                exit(1)
        else:
            for config_file in (
                __file__[: __file__.rfind(".")] + ".cfg",
                "./lcm.cfg",
                "/etc/osm/lcm.cfg",
            ):
                if path.isfile(config_file):
                    break
            else:
                print(
                    "No configuration file 'lcm.cfg' found neither at local folder nor at /etc/osm/",
                    file=sys.stderr,
                )
                exit(1)
        lcm = Lcm(config_file)
        asyncio.run(lcm.start())
    except (LcmException, getopt.GetoptError) as e:
        print(str(e), file=sys.stderr)
        # usage()
        exit(1)
