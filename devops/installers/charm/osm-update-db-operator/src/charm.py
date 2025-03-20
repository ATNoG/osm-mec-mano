#!/usr/bin/env python3
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

"""Update DB charm module."""

import logging

from ops.charm import CharmBase
from ops.framework import StoredState
from ops.main import main
from ops.model import ActiveStatus, BlockedStatus

from db_upgrade import MongoUpgrade, MysqlUpgrade

logger = logging.getLogger(__name__)


class UpgradeDBCharm(CharmBase):
    """Upgrade DB Charm operator."""

    _stored = StoredState()

    def __init__(self, *args):
        super().__init__(*args)

        # Observe events
        event_observe_mapping = {
            self.on.update_db_action: self._on_update_db_action,
            self.on.apply_patch_action: self._on_apply_patch_action,
            self.on.config_changed: self._on_config_changed,
        }
        for event, observer in event_observe_mapping.items():
            self.framework.observe(event, observer)

    @property
    def mongo(self):
        """Create MongoUpgrade object if the configuration has been set."""
        mongo_uri = self.config.get("mongodb-uri")
        return MongoUpgrade(mongo_uri) if mongo_uri else None

    @property
    def mysql(self):
        """Create MysqlUpgrade object if the configuration has been set."""
        mysql_uri = self.config.get("mysql-uri")
        return MysqlUpgrade(mysql_uri) if mysql_uri else None

    def _on_config_changed(self, _):
        mongo_uri = self.config.get("mongodb-uri")
        mysql_uri = self.config.get("mysql-uri")
        if not mongo_uri and not mysql_uri:
            self.unit.status = BlockedStatus("mongodb-uri and/or mysql-uri must be set")
            return
        self.unit.status = ActiveStatus()

    def _on_update_db_action(self, event):
        """Handle the update-db action."""
        current_version = str(event.params["current-version"])
        target_version = str(event.params["target-version"])
        mysql_only = event.params.get("mysql-only")
        mongodb_only = event.params.get("mongodb-only")
        try:
            results = {}
            if mysql_only and mongodb_only:
                raise Exception("cannot set both mysql-only and mongodb-only options to True")
            if mysql_only:
                self._upgrade_mysql(current_version, target_version)
                results["mysql"] = "Upgraded successfully"
            elif mongodb_only:
                self._upgrade_mongodb(current_version, target_version)
                results["mongodb"] = "Upgraded successfully"
            else:
                self._upgrade_mysql(current_version, target_version)
                results["mysql"] = "Upgraded successfully"
                self._upgrade_mongodb(current_version, target_version)
                results["mongodb"] = "Upgraded successfully"
            event.set_results(results)
        except Exception as e:
            event.fail(f"Failed DB Upgrade: {e}")

    def _upgrade_mysql(self, current_version, target_version):
        logger.debug("Upgrading mysql")
        if self.mysql:
            self.mysql.upgrade(current_version, target_version)
        else:
            raise Exception("mysql-uri not set")

    def _upgrade_mongodb(self, current_version, target_version):
        logger.debug("Upgrading mongodb")
        if self.mongo:
            self.mongo.upgrade(current_version, target_version)
        else:
            raise Exception("mongo-uri not set")

    def _on_apply_patch_action(self, event):
        bug_number = event.params["bug-number"]
        logger.debug("Patching bug number {}".format(str(bug_number)))
        try:
            if self.mongo:
                self.mongo.apply_patch(bug_number)
            else:
                raise Exception("mongo-uri not set")
        except Exception as e:
            event.fail(f"Failed Patch Application: {e}")


if __name__ == "__main__":  # pragma: no cover
    main(UpgradeDBCharm, use_juju_for_storage=True)
