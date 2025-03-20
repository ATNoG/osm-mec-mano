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
#
# For those usages not covered by the Apache License, Version 2.0 please
# contact: legal@canonical.com
#
# To get in touch with the maintainers, please contact:
# osm-charmers@lists.launchpad.net
#
# flake8: noqa

import ops


class BaseRelationClient(ops.framework.Object):
    """Requires side of a Kafka Endpoint"""

    def __init__(
        self,
        charm: ops.charm.CharmBase,
        relation_name: str,
        mandatory_fields: list = [],
    ):
        super().__init__(charm, relation_name)
        self.relation_name = relation_name
        self.mandatory_fields = mandatory_fields
        self._update_relation()

    def get_data_from_unit(self, key: str):
        if not self.relation:
            # This update relation doesn't seem to be needed, but I added it because apparently
            # the data is empty in the unit tests.
            # In reality, the constructor is called in every hook.
            # In the unit tests when doing an update_relation_data, apparently it is not called.
            self._update_relation()
        if self.relation:
            for unit in self.relation.units:
                data = self.relation.data[unit].get(key)
                if data:
                    return data

    def get_data_from_app(self, key: str):
        if not self.relation or self.relation.app not in self.relation.data:
            # This update relation doesn't seem to be needed, but I added it because apparently
            # the data is empty in the unit tests.
            # In reality, the constructor is called in every hook.
            # In the unit tests when doing an update_relation_data, apparently it is not called.
            self._update_relation()
        if self.relation and self.relation.app in self.relation.data:
            data = self.relation.data[self.relation.app].get(key)
            if data:
                return data

    def is_missing_data_in_unit(self):
        return not all([self.get_data_from_unit(field) for field in self.mandatory_fields])

    def is_missing_data_in_app(self):
        return not all([self.get_data_from_app(field) for field in self.mandatory_fields])

    def _update_relation(self):
        self.relation = self.framework.model.get_relation(self.relation_name)


class KeystoneClient(BaseRelationClient):
    """Requires side of a Keystone Endpoint"""

    mandatory_fields = [
        "host",
        "port",
        "user_domain_name",
        "project_domain_name",
        "username",
        "password",
        "service",
        "keystone_db_password",
        "region_id",
        "admin_username",
        "admin_password",
        "admin_project_name",
    ]

    def __init__(self, charm: ops.charm.CharmBase, relation_name: str):
        super().__init__(charm, relation_name, self.mandatory_fields)

    @property
    def host(self):
        return self.get_data_from_app("host")

    @property
    def port(self):
        return self.get_data_from_app("port")

    @property
    def user_domain_name(self):
        return self.get_data_from_app("user_domain_name")

    @property
    def project_domain_name(self):
        return self.get_data_from_app("project_domain_name")

    @property
    def username(self):
        return self.get_data_from_app("username")

    @property
    def password(self):
        return self.get_data_from_app("password")

    @property
    def service(self):
        return self.get_data_from_app("service")

    @property
    def keystone_db_password(self):
        return self.get_data_from_app("keystone_db_password")

    @property
    def region_id(self):
        return self.get_data_from_app("region_id")

    @property
    def admin_username(self):
        return self.get_data_from_app("admin_username")

    @property
    def admin_password(self):
        return self.get_data_from_app("admin_password")

    @property
    def admin_project_name(self):
        return self.get_data_from_app("admin_project_name")


class MongoClient(BaseRelationClient):
    """Requires side of a Mongo Endpoint"""

    mandatory_fields_mapping = {
        "reactive": ["connection_string"],
        "ops": ["replica_set_uri", "replica_set_name"],
    }

    def __init__(self, charm: ops.charm.CharmBase, relation_name: str):
        super().__init__(charm, relation_name, mandatory_fields=[])

    @property
    def connection_string(self):
        if self.is_opts():
            replica_set_uri = self.get_data_from_unit("replica_set_uri")
            replica_set_name = self.get_data_from_unit("replica_set_name")
            return f"{replica_set_uri}?replicaSet={replica_set_name}"
        else:
            return self.get_data_from_unit("connection_string")

    def is_opts(self):
        return not self.is_missing_data_in_unit_ops()

    def is_missing_data_in_unit(self):
        return self.is_missing_data_in_unit_ops() and self.is_missing_data_in_unit_reactive()

    def is_missing_data_in_unit_ops(self):
        return not all(
            [self.get_data_from_unit(field) for field in self.mandatory_fields_mapping["ops"]]
        )

    def is_missing_data_in_unit_reactive(self):
        return not all(
            [self.get_data_from_unit(field) for field in self.mandatory_fields_mapping["reactive"]]
        )


class PrometheusClient(BaseRelationClient):
    """Requires side of a Prometheus Endpoint"""

    mandatory_fields = ["hostname", "port"]

    def __init__(self, charm: ops.charm.CharmBase, relation_name: str):
        super().__init__(charm, relation_name, self.mandatory_fields)

    @property
    def hostname(self):
        return self.get_data_from_app("hostname")

    @property
    def port(self):
        return self.get_data_from_app("port")

    @property
    def user(self):
        return self.get_data_from_app("user")

    @property
    def password(self):
        return self.get_data_from_app("password")
