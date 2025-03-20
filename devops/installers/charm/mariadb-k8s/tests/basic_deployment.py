#!/usr/bin/python3
# Copyright 2021 Canonical Ltd.
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
##

import unittest
import zaza.model as model

import mysql.connector as mysql

# from mysql.connector import errorcode

APPLICATION_NAME = "mariadb-k8s"
UNIT_NAME = "mariadb-k8s/0"
ROOT_USER = "root"
ROOT_PASSWORD = "osm4u"
USER = "mano"
PASSWORD = "manopw"
ACTION_SUCCESS_STATUS = "completed"


def create_database(cnx, database_name):
    try:
        if not database_exists(cnx, database_name):
            cursor = cnx.cursor()
            cursor.execute(
                "CREATE DATABASE {} DEFAULT CHARACTER SET 'utf8'".format(database_name)
            )
            return database_exists(cnx, database_name)
        else:
            return True
    except mysql.Error as err:
        print("Failed creating database {}: {}".format(database_name, err))


def delete_database(cnx, database_name):
    try:
        if database_exists(cnx, database_name):
            cursor = cnx.cursor()
            cursor.execute("DROP DATABASE {}".format(database_name))
            return not database_exists(cnx, database_name)
        else:
            return True
    except mysql.Error as err:
        print("Failed deleting database {}: {}".format(database_name, err))


def database_exists(cnx, database_name):
    try:
        cursor = cnx.cursor()
        cursor.execute("SHOW DATABASES")
        databases = cursor.fetchall()
        exists = False
        for database in databases:
            if database[0] == database_name:
                exists = True
        cursor.close()
        return exists
    except mysql.Error as err:
        print("Failed deleting database {}: {}".format(database_name, err))
        return False


class BasicDeployment(unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.ip = model.get_status().applications[APPLICATION_NAME]["public-address"]
        try:
            self.cnx = mysql.connect(
                user=ROOT_USER, password=ROOT_PASSWORD, host=self.ip
            )
        except mysql.Error as err:
            print("Couldn't connect to mariadb-k8s : {}".format(err))

    def tearDown(self):
        super().tearDown()
        self.cnx.close()

    def test_mariadb_connection_root(self):
        pass

    def test_mariadb_connection_user(self):
        try:
            cnx = mysql.connect(user=USER, password=PASSWORD, host=self.ip)
            cnx.close()
        except mysql.Error as err:
            print("Couldn't connect to mariadb-k8s with user creds: {}".format(err))

    def test_mariadb_create_database(self):
        created = create_database(self.cnx, "test_database")
        self.failIf(not created)

    def test_mariadb_backup_action(self, db_name="test_backup"):
        created = create_database(self.cnx, db_name)
        self.failIf(not created)
        try:
            action = model.run_action(UNIT_NAME, "backup", raise_on_failure=True)
            self.assertEqual(action.status, ACTION_SUCCESS_STATUS)
        except model.ActionFailed as err:
            print("Action failed: {}".format(err))

    def test_mariadb_remove_backup_action(self):
        self.test_mariadb_backup_action(db_name="test_remove_backup")
        try:
            action = model.run_action(UNIT_NAME, "remove-backup", raise_on_failure=True)
            self.assertEqual(action.status, ACTION_SUCCESS_STATUS)
        except model.ActionFailed as err:
            print("Action failed: {}".format(err))

    def test_mariadb_restore_action(self):
        self.test_mariadb_backup_action(db_name="test_restore")
        deleted = delete_database(self.cnx, "test_restore")
        self.failIf(not deleted)
        try:
            action = model.run_action(UNIT_NAME, "restore", raise_on_failure=True)
            self.assertEqual(action.status, "completed")
            self.assertTrue(database_exists(self.cnx, "test_restore"))
        except model.ActionFailed as err:
            print("Action failed: {}".format(err))
