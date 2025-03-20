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

import logging
from urllib.parse import quote

from osm_common.dbbase import DbException, FakeLock
from osm_common.dbmongo import DbMongo
from pymongo import MongoClient
import pytest


def db_status_exception_message():
    return "database exception Wrong database status"


def db_version_exception_message():
    return "database exception Invalid database version"


def mock_get_one_status_not_enabled(a, b, c, fail_on_empty=False, fail_on_more=True):
    return {"status": "ERROR", "version": "", "serial": ""}


def mock_get_one_wrong_db_version(a, b, c, fail_on_empty=False, fail_on_more=True):
    return {"status": "ENABLED", "version": "4.0", "serial": "MDY4OA=="}


def db_generic_exception(exception):
    return exception


def db_generic_exception_message(message):
    return f"database exception {message}"


def test_constructor():
    db = DbMongo(lock=True)
    assert db.logger == logging.getLogger("db")
    assert db.db is None
    assert db.client is None
    assert db.database_key is None
    assert db.secret_obtained is False
    assert db.lock.acquire() is True


def test_constructor_with_logger():
    logger_name = "db_mongo"
    db = DbMongo(logger_name=logger_name, lock=False)
    assert db.logger == logging.getLogger(logger_name)
    assert db.db is None
    assert db.client is None
    assert db.database_key is None
    assert db.secret_obtained is False
    assert type(db.lock) == FakeLock


@pytest.mark.parametrize(
    "config, target_version, serial, lock",
    [
        (
            {
                "logger_name": "mongo_logger",
                "commonkey": "common",
                "uri": "mongo:27017",
                "replicaset": "rs0",
                "name": "osmdb",
                "loglevel": "CRITICAL",
            },
            "5.0",
            "MDY=",
            True,
        ),
        (
            {
                "logger_name": "mongo_logger",
                "commonkey": "common",
                "masterpassword": "master",
                "uri": "mongo:27017",
                "replicaset": "rs0",
                "name": "osmdb",
                "loglevel": "CRITICAL",
            },
            "5.0",
            "MDY=",
            False,
        ),
        (
            {
                "logger_name": "logger",
                "uri": "mongo:27017",
                "name": "newdb",
                "commonkey": "common",
            },
            "3.6",
            "",
            True,
        ),
        (
            {
                "uri": "mongo:27017",
                "commonkey": "common",
                "name": "newdb",
            },
            "5.0",
            "MDIy",
            False,
        ),
        (
            {
                "uri": "mongo:27017",
                "masterpassword": "common",
                "name": "newdb",
                "loglevel": "CRITICAL",
            },
            "4.4",
            "OTA=",
            False,
        ),
        (
            {
                "uri": "mongo",
                "masterpassword": "common",
                "name": "osmdb",
                "loglevel": "CRITICAL",
            },
            "4.4",
            "OTA=",
            True,
        ),
        (
            {
                "logger_name": "mongo_logger",
                "commonkey": "common",
                "uri": quote("user4:password4@mongo"),
                "replicaset": "rs0",
                "name": "osmdb",
                "loglevel": "CRITICAL",
            },
            "5.0",
            "NTM=",
            True,
        ),
        (
            {
                "logger_name": "logger",
                "uri": quote("user3:password3@mongo:27017"),
                "name": "newdb",
                "commonkey": "common",
            },
            "4.0",
            "NjEx",
            False,
        ),
        (
            {
                "uri": quote("user2:password2@mongo:27017"),
                "commonkey": "common",
                "name": "newdb",
            },
            "5.0",
            "cmV0MzI=",
            False,
        ),
        (
            {
                "uri": quote("user1:password1@mongo:27017"),
                "commonkey": "common",
                "masterpassword": "master",
                "name": "newdb",
                "loglevel": "CRITICAL",
            },
            "4.0",
            "MjMyNQ==",
            False,
        ),
        (
            {
                "uri": quote("user1:password1@mongo"),
                "masterpassword": "common",
                "name": "newdb",
                "loglevel": "CRITICAL",
            },
            "4.0",
            "MjMyNQ==",
            True,
        ),
    ],
)
def test_db_connection_with_valid_config(
    config, target_version, serial, lock, monkeypatch
):
    def mock_get_one(a, b, c, fail_on_empty=False, fail_on_more=True):
        return {"status": "ENABLED", "version": target_version, "serial": serial}

    monkeypatch.setattr(DbMongo, "get_one", mock_get_one)
    db = DbMongo(lock=lock)
    db.db_connect(config, target_version)
    assert (
        db.logger == logging.getLogger(config.get("logger_name"))
        if config.get("logger_name")
        else logging.getLogger("db")
    )
    assert type(db.client) == MongoClient
    assert db.database_key == "common"
    assert db.logger.getEffectiveLevel() == 50 if config.get("loglevel") else 20


@pytest.mark.parametrize(
    "config, target_version, version_data, expected_exception_message",
    [
        (
            {
                "logger_name": "mongo_logger",
                "commonkey": "common",
                "uri": "mongo:27017",
                "replicaset": "rs2",
                "name": "osmdb",
                "loglevel": "CRITICAL",
            },
            "4.0",
            mock_get_one_status_not_enabled,
            db_status_exception_message(),
        ),
        (
            {
                "logger_name": "mongo_logger",
                "commonkey": "common",
                "uri": "mongo:27017",
                "replicaset": "rs4",
                "name": "osmdb",
                "loglevel": "CRITICAL",
            },
            "5.0",
            mock_get_one_wrong_db_version,
            db_version_exception_message(),
        ),
        (
            {
                "logger_name": "mongo_logger",
                "commonkey": "common",
                "uri": quote("user2:pa@word2@mongo:27017"),
                "replicaset": "rs0",
                "name": "osmdb",
                "loglevel": "DEBUG",
            },
            "4.0",
            mock_get_one_status_not_enabled,
            db_status_exception_message(),
        ),
        (
            {
                "logger_name": "mongo_logger",
                "commonkey": "common",
                "uri": quote("username:pass1rd@mongo:27017"),
                "replicaset": "rs0",
                "name": "osmdb",
                "loglevel": "DEBUG",
            },
            "5.0",
            mock_get_one_wrong_db_version,
            db_version_exception_message(),
        ),
    ],
)
def test_db_connection_db_status_error(
    config, target_version, version_data, expected_exception_message, monkeypatch
):
    monkeypatch.setattr(DbMongo, "get_one", version_data)
    db = DbMongo(lock=False)
    with pytest.raises(DbException) as exception_info:
        db.db_connect(config, target_version)
    assert str(exception_info.value).startswith(expected_exception_message)


@pytest.mark.parametrize(
    "config, target_version, lock, expected_exception",
    [
        (
            {
                "logger_name": "mongo_logger",
                "commonkey": "common",
                "uri": "27017@/:",
                "replicaset": "rs0",
                "name": "osmdb",
                "loglevel": "CRITICAL",
            },
            "4.0",
            True,
            db_generic_exception(DbException),
        ),
        (
            {
                "logger_name": "mongo_logger",
                "commonkey": "common",
                "uri": "user@pass",
                "replicaset": "rs0",
                "name": "osmdb",
                "loglevel": "CRITICAL",
            },
            "4.0",
            False,
            db_generic_exception(DbException),
        ),
        (
            {
                "logger_name": "mongo_logger",
                "commonkey": "common",
                "uri": "user@pass:27017",
                "replicaset": "rs0",
                "name": "osmdb",
                "loglevel": "CRITICAL",
            },
            "4.0",
            True,
            db_generic_exception(DbException),
        ),
        (
            {
                "logger_name": "mongo_logger",
                "commonkey": "common",
                "uri": "",
                "replicaset": "rs0",
                "name": "osmdb",
                "loglevel": "CRITICAL",
            },
            "5.0",
            False,
            db_generic_exception(TypeError),
        ),
        (
            {
                "logger_name": "mongo_logger",
                "commonkey": "common",
                "uri": "user2::@mon:27017",
                "replicaset": "rs0",
                "name": "osmdb",
                "loglevel": "DEBUG",
            },
            "4.0",
            True,
            db_generic_exception(ValueError),
        ),
        (
            {
                "logger_name": "mongo_logger",
                "commonkey": "common",
                "replicaset": 33,
                "uri": "user2@@mongo:27017",
                "name": "osmdb",
                "loglevel": "DEBUG",
            },
            "5.0",
            False,
            db_generic_exception(TypeError),
        ),
    ],
)
def test_db_connection_with_invalid_uri(
    config, target_version, lock, expected_exception, monkeypatch
):
    def mock_get_one(a, b, c, fail_on_empty=False, fail_on_more=True):
        pass

    monkeypatch.setattr(DbMongo, "get_one", mock_get_one)
    db = DbMongo(lock=lock)
    with pytest.raises(expected_exception) as exception_info:
        db.db_connect(config, target_version)
    assert type(exception_info.value) == expected_exception


@pytest.mark.parametrize(
    "config, target_version, expected_exception",
    [
        (
            {
                "logger_name": "mongo_logger",
                "commonkey": "common",
                "replicaset": "rs0",
                "name": "osmdb",
                "loglevel": "CRITICAL",
            },
            "",
            db_generic_exception(TypeError),
        ),
        (
            {
                "logger_name": "mongo_logger",
                "uri": "mongo:27017",
                "replicaset": "rs0",
                "loglevel": "CRITICAL",
            },
            "4.0",
            db_generic_exception(KeyError),
        ),
        (
            {
                "replicaset": "rs0",
                "loglevel": "CRITICAL",
            },
            None,
            db_generic_exception(KeyError),
        ),
        (
            {
                "logger_name": "mongo_logger",
                "commonkey": "common",
                "uri": "",
                "replicaset": "rs0",
                "name": "osmdb",
                "loglevel": "CRITICAL",
            },
            "5.0",
            db_generic_exception(TypeError),
        ),
        (
            {
                "logger_name": "mongo_logger",
                "name": "osmdb",
            },
            "4.0",
            db_generic_exception(TypeError),
        ),
        (
            {
                "logger_name": "logger",
                "replicaset": "",
                "uri": "user2@@mongo:27017",
            },
            "5.0",
            db_generic_exception(KeyError),
        ),
    ],
)
def test_db_connection_with_missing_parameters(
    config, target_version, expected_exception, monkeypatch
):
    def mock_get_one(a, b, c, fail_on_empty=False, fail_on_more=True):
        return

    monkeypatch.setattr(DbMongo, "get_one", mock_get_one)
    db = DbMongo(lock=False)
    with pytest.raises(expected_exception) as exception_info:
        db.db_connect(config, target_version)
    assert type(exception_info.value) == expected_exception


@pytest.mark.parametrize(
    "config, expected_exception_message",
    [
        (
            {
                "logger_name": "mongo_logger",
                "commonkey": "common",
                "uri": "mongo:27017",
                "replicaset": "rs0",
                "name": "osmdb1",
                "loglevel": "CRITICAL",
            },
            "MongoClient crashed",
        ),
        (
            {
                "logger_name": "mongo_logger",
                "commonkey": "common",
                "uri": "username:pas1ed@mongo:27017",
                "replicaset": "rs1",
                "name": "osmdb2",
                "loglevel": "DEBUG",
            },
            "MongoClient crashed",
        ),
    ],
)
def test_db_connection_with_invalid_mongoclient(
    config, expected_exception_message, monkeypatch
):
    def generate_exception(a, b, replicaSet=None):
        raise DbException(expected_exception_message)

    monkeypatch.setattr(MongoClient, "__init__", generate_exception)
    db = DbMongo()
    with pytest.raises(DbException) as exception_info:
        db.db_connect(config)
    assert str(exception_info.value) == db_generic_exception_message(
        expected_exception_message
    )
