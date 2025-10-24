#!/usr/bin/env python

# Copyright 2021 Whitestack, LLC
# *************************************************************

# This file is part of OSM Monitoring module
# All Rights Reserved to Whitestack, LLC

# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at

#         http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

# For those usages not covered by the Apache License, Version 2.0 please
# contact: fbravo@whitestack.com
##

import aiohttp
import asyncio
from bson.json_util import dumps
from bson import ObjectId
import copy
from datetime import datetime
import json
import os
import pymongo
import time
import yaml

# Env variables
mongodb_url = os.environ["MONGODB_URL"]
target_database = os.environ["TARGET_DATABASE"]
prometheus_config_file = os.environ["PROMETHEUS_CONFIG_FILE"]
prometheus_base_config_file = os.environ["PROMETHEUS_BASE_CONFIG_FILE"]
prometheus_alerts_file = os.environ["PROMETHEUS_ALERTS_FILE"]
prometheus_base_alerts_file = os.environ["PROMETHEUS_BASE_ALERTS_FILE"]

prometheus_url = os.environ["PROMETHEUS_URL"]


def get_jobs(client):
    return json.loads(dumps(client[target_database].prometheus_jobs.find({})))


def get_alerts(client):
    return json.loads(dumps(client[target_database].alerts.find({"prometheus_config": {"$exists": True}})))


def save_successful_jobs(client, jobs):
    for job in jobs:
        client[target_database].prometheus_jobs.update_one(
            {"_id": ObjectId(job["_id"]["$oid"])}, {"$set": {"is_active": True}}
        )


def clean_up_job(prometheus_job):
    cleaned_prometheus_job = copy.deepcopy(prometheus_job)
    # take out _id and internal keys
    cleaned_prometheus_job.pop("_id", None)
    cleaned_prometheus_job.pop("is_active", None)
    cleaned_prometheus_job.pop("vnfr_id", None)
    cleaned_prometheus_job.pop("nsr_id", None)
    return cleaned_prometheus_job


def generate_prometheus_config(prometheus_jobs, config_file_path):
    with open(config_file_path, encoding="utf-8", mode="r") as config_file:
        config_file_yaml = yaml.safe_load(config_file)
    if config_file_yaml is None:
        config_file_yaml = {}
    if "scrape_configs" not in config_file_yaml:
        config_file_yaml["scrape_configs"] = []

    prometheus_jobs_to_be_added = []

    for prometheus_job in prometheus_jobs:
        cleaned_up_job = clean_up_job(prometheus_job)
        job_to_be_added = True
        for sc in config_file_yaml["scrape_configs"]:
            if sc.get("job_name") == cleaned_up_job.get("job_name"):
                job_to_be_added = False
                break
        if job_to_be_added:
            prometheus_jobs_to_be_added.append(cleaned_up_job)

    for job in prometheus_jobs_to_be_added:
        config_file_yaml["scrape_configs"].append(job)

    return config_file_yaml


def generate_prometheus_alerts(prometheus_alerts, config_file_path):
    with open(config_file_path, encoding="utf-8", mode="r") as config_file:
        config_file_yaml = yaml.safe_load(config_file)
    if config_file_yaml is None:
        config_file_yaml = {}
    if "groups" not in config_file_yaml:
        config_file_yaml["groups"] = []

    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    group = {
        "name": f"_osm_alert_rules_{timestamp}_",
        "rules": [],
    }
    for alert in prometheus_alerts:
        if "prometheus_config" in alert:
            group["rules"].append(alert["prometheus_config"])

    if group["rules"]:
        config_file_yaml["groups"].append(group)

    return config_file_yaml


async def reload_prometheus_config(prom_url):
    async with aiohttp.ClientSession() as session:
        async with session.post(prom_url + "/-/reload") as resp:
            if resp.status > 204:
                print(f"Error while updating prometheus config: {resp.text()}")
                return False
        await asyncio.sleep(5)
        return True


def check_configuration_equal(a_config, b_config):
    if a_config is None and b_config is None:
        return True
    if a_config is None or b_config is None:
        return False
    if "scrape_configs" not in a_config and "scrape_configs" not in b_config:
        return True
    if "scrape_configs" not in a_config or "scrape_configs" not in b_config:
        return False
    a_jobs = [j["job_name"] for j in a_config["scrape_configs"]]
    b_jobs = [j["job_name"] for j in b_config["scrape_configs"]]

    return a_jobs == b_jobs


async def validate_configuration(prom_url, new_config):
    async with aiohttp.ClientSession() as session:
        # Gets the configuration from prometheus
        # and compares with the inserted one
        # If prometheus does not admit this configuration,
        # the old one will remain
        async with session.get(prom_url + "/api/v1/status/config") as resp:
            if resp.status > 204:
                print(f"Error while updating prometheus config: {resp.text()}")
                return False
            current_config = await resp.json()
            return check_configuration_equal(
                yaml.safe_load(current_config["data"]["yaml"]), new_config
            )


async def main_task(client):
    stored_jobs = get_jobs(client)
    print(f"Jobs detected: {len(stored_jobs):d}")
    generated_prometheus_config = generate_prometheus_config(
        stored_jobs, prometheus_base_config_file
    )
    print(f"Writing new config file to {prometheus_config_file}")
    config_file = open(prometheus_config_file, "w")
    config_file.truncate(0)
    print(yaml.safe_dump(generated_prometheus_config))
    config_file.write(yaml.safe_dump(generated_prometheus_config))
    config_file.close()

    if os.path.isfile(prometheus_base_alerts_file):
        stored_alerts = get_alerts(client)
        print(f"Alerts read: {len(stored_alerts):d}")
        generated_prometheus_alerts = generate_prometheus_alerts(
            stored_alerts, prometheus_base_alerts_file
        )
        print(f"Writing new alerts file to {prometheus_alerts_file}")
        config_file = open(prometheus_alerts_file, "w")
        config_file.truncate(0)
        print(yaml.safe_dump(generated_prometheus_alerts))
        config_file.write(yaml.safe_dump(generated_prometheus_alerts))
        config_file.close()

    print("New config written, updating prometheus")
    update_resp = await reload_prometheus_config(prometheus_url)
    is_valid = await validate_configuration(prometheus_url, generated_prometheus_config)
    if update_resp and is_valid:
        print("Prometheus config update successful")
        save_successful_jobs(client, stored_jobs)
    else:
        print(
            "Error while updating prometheus config: "
            "current config doesn't match with updated values"
        )


async def main():
    client = pymongo.MongoClient(mongodb_url)
    print("Created MongoClient to connect to MongoDB!")

    # Initial loop. First refresh of prometheus config file
    first_refresh_completed = False
    tries = 1
    while tries <= 3 and first_refresh_completed == False:
        try:
            print("Generating prometheus config files")
            await main_task(client)
            first_refresh_completed = True
        except Exception as error:
            print(f"Error in configuration attempt! Number of tries: {tries}/3")
            print(error)
        time.sleep(5)
        tries += 1
    if not first_refresh_completed:
        print("Not possible to refresh prometheus config file for first time")
        return

    # Main loop
    while True:
        try:
            # Needs mongodb in replica mode as this feature relies in OpLog
            change_stream = client[target_database].watch(
                [
                    {
                        "$match": {
                            "operationType": {"$in": ["insert", "delete"]},
                            "ns.coll": { "$in": ["prometheus_jobs", "alerts"]},
                        }
                    }
                ]
            )

            # Single thread, no race conditions and ops are queued up in order
            print("Listening to changes in prometheus jobs and alerts collections")
            for change in change_stream:
                print("Changes detected, updating prometheus config")
                await main_task(client)
                print()
        except Exception as error:
            print(error)
        print(
            "Detected failure while listening to prometheus jobs collection, "
            "retrying..."
        )
        time.sleep(5)


asyncio.run(main())
