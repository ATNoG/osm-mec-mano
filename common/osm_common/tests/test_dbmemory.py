# Copyright 2018 Whitestack, LLC
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
#
# For those usages not covered by the Apache License, Version 2.0 please
# contact: esousa@whitestack.com or alfonso.tiernosepulveda@telefonica.com
##
from copy import deepcopy
import http
import logging
import unittest
from unittest.mock import MagicMock, Mock

from osm_common.dbbase import DbException
from osm_common.dbmemory import DbMemory
import pytest

__author__ = "Eduardo Sousa <eduardosousa@av.it.pt>"


@pytest.fixture(scope="function", params=[True, False])
def db_memory(request):
    db = DbMemory(lock=request.param)
    return db


@pytest.fixture(scope="function", params=[True, False])
def db_memory_with_data(request):
    db = DbMemory(lock=request.param)

    db.create("test", {"_id": 1, "data": 1})
    db.create("test", {"_id": 2, "data": 2})
    db.create("test", {"_id": 3, "data": 3})

    return db


@pytest.fixture(scope="function")
def db_memory_with_many_data(request):
    db = DbMemory(lock=False)

    db.create_list(
        "test",
        [
            {
                "_id": 1,
                "data": {"data2": {"data3": 1}},
                "list": [{"a": 1}],
                "text": "sometext",
            },
            {
                "_id": 2,
                "data": {"data2": {"data3": 2}},
                "list": [{"a": 2}],
                "list2": [1, 2, 3],
            },
            {"_id": 3, "data": {"data2": {"data3": 3}}, "list": [{"a": 3}]},
            {"_id": 4, "data": {"data2": {"data3": 4}}, "list": [{"a": 4}, {"a": 0}]},
            {"_id": 5, "data": {"data2": {"data3": 5}}, "list": [{"a": 5}]},
            {"_id": 6, "data": {"data2": {"data3": 6}}, "list": [{"0": {"a": 1}}]},
            {"_id": 7, "data": {"data2": {"data3": 7}}, "0": {"a": 0}},
            {
                "_id": 8,
                "list": [
                    {"a": 3, "b": 0, "c": [{"a": 3, "b": 1}, {"a": 0, "b": "v"}]},
                    {"a": 0, "b": 1},
                ],
            },
        ],
    )
    return db


def empty_exception_message():
    return "database exception "


def get_one_exception_message(db_filter):
    return "database exception Not found entry with filter='{}'".format(db_filter)


def get_one_multiple_exception_message(db_filter):
    return "database exception Found more than one entry with filter='{}'".format(
        db_filter
    )


def del_one_exception_message(db_filter):
    return "database exception Not found entry with filter='{}'".format(db_filter)


def replace_exception_message(value):
    return "database exception Not found entry with _id='{}'".format(value)


def test_constructor():
    db = DbMemory()
    assert db.logger == logging.getLogger("db")
    assert db.db == {}


def test_constructor_with_logger():
    logger_name = "db_local"
    db = DbMemory(logger_name=logger_name)
    assert db.logger == logging.getLogger(logger_name)
    assert db.db == {}


def test_db_connect():
    logger_name = "db_local"
    config = {"logger_name": logger_name}
    db = DbMemory()
    db.db_connect(config)
    assert db.logger == logging.getLogger(logger_name)
    assert db.db == {}


def test_db_disconnect(db_memory):
    db_memory.db_disconnect()


@pytest.mark.parametrize(
    "table, db_filter",
    [
        ("test", {}),
        ("test", {"_id": 1}),
        ("test", {"data": 1}),
        ("test", {"_id": 1, "data": 1}),
    ],
)
def test_get_list_with_empty_db(db_memory, table, db_filter):
    result = db_memory.get_list(table, db_filter)
    assert len(result) == 0


@pytest.mark.parametrize(
    "table, db_filter, expected_data",
    [
        (
            "test",
            {},
            [{"_id": 1, "data": 1}, {"_id": 2, "data": 2}, {"_id": 3, "data": 3}],
        ),
        ("test", {"_id": 1}, [{"_id": 1, "data": 1}]),
        ("test", {"data": 1}, [{"_id": 1, "data": 1}]),
        ("test", {"_id": 1, "data": 1}, [{"_id": 1, "data": 1}]),
        ("test", {"_id": 2}, [{"_id": 2, "data": 2}]),
        ("test", {"data": 2}, [{"_id": 2, "data": 2}]),
        ("test", {"_id": 2, "data": 2}, [{"_id": 2, "data": 2}]),
        ("test", {"_id": 4}, []),
        ("test", {"data": 4}, []),
        ("test", {"_id": 4, "data": 4}, []),
        ("test_table", {}, []),
        ("test_table", {"_id": 1}, []),
        ("test_table", {"data": 1}, []),
        ("test_table", {"_id": 1, "data": 1}, []),
    ],
)
def test_get_list_with_non_empty_db(
    db_memory_with_data, table, db_filter, expected_data
):
    result = db_memory_with_data.get_list(table, db_filter)
    assert len(result) == len(expected_data)
    for data in expected_data:
        assert data in result


def test_get_list_exception(db_memory_with_data):
    table = "test"
    db_filter = {}
    db_memory_with_data._find = MagicMock(side_effect=Exception())
    with pytest.raises(DbException) as excinfo:
        db_memory_with_data.get_list(table, db_filter)
    assert str(excinfo.value) == empty_exception_message()
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


@pytest.mark.parametrize(
    "table, db_filter, expected_data",
    [
        ("test", {"_id": 1}, {"_id": 1, "data": 1}),
        ("test", {"_id": 2}, {"_id": 2, "data": 2}),
        ("test", {"_id": 3}, {"_id": 3, "data": 3}),
        ("test", {"data": 1}, {"_id": 1, "data": 1}),
        ("test", {"data": 2}, {"_id": 2, "data": 2}),
        ("test", {"data": 3}, {"_id": 3, "data": 3}),
        ("test", {"_id": 1, "data": 1}, {"_id": 1, "data": 1}),
        ("test", {"_id": 2, "data": 2}, {"_id": 2, "data": 2}),
        ("test", {"_id": 3, "data": 3}, {"_id": 3, "data": 3}),
    ],
)
def test_get_one(db_memory_with_data, table, db_filter, expected_data):
    result = db_memory_with_data.get_one(table, db_filter)
    assert result == expected_data
    assert len(db_memory_with_data.db) == 1
    assert table in db_memory_with_data.db
    assert len(db_memory_with_data.db[table]) == 3
    assert result in db_memory_with_data.db[table]


@pytest.mark.parametrize(
    "db_filter, expected_ids",
    [
        ({}, [1, 2, 3, 4, 5, 6, 7, 8]),
        ({"_id": 1}, [1]),
        ({"data.data2.data3": 2}, [2]),
        ({"data.data2.data3.eq": 2}, [2]),
        ({"data.data2.data3": [2]}, [2]),
        ({"data.data2.data3.cont": [2]}, [2]),
        ({"data.data2.data3.neq": 2}, [1, 3, 4, 5, 6, 7, 8]),
        ({"data.data2.data3.neq": [2]}, [1, 3, 4, 5, 6, 7, 8]),
        ({"data.data2.data3.ncont": [2]}, [1, 3, 4, 5, 6, 7, 8]),
        ({"data.data2.data3": [2, 3]}, [2, 3]),
        ({"data.data2.data3.gt": 4}, [5, 6, 7]),
        ({"data.data2.data3.gte": 4}, [4, 5, 6, 7]),
        ({"data.data2.data3.lt": 4}, [1, 2, 3]),
        ({"data.data2.data3.lte": 4}, [1, 2, 3, 4]),
        ({"data.data2.data3.lte": 4.5}, [1, 2, 3, 4]),
        ({"data.data2.data3.gt": "text"}, []),
        ({"nonexist.nonexist": "4"}, []),
        ({"nonexist.nonexist": None}, [1, 2, 3, 4, 5, 6, 7, 8]),
        ({"nonexist.nonexist.neq": "4"}, [1, 2, 3, 4, 5, 6, 7, 8]),
        ({"nonexist.nonexist.neq": None}, []),
        ({"text.eq": "sometext"}, [1]),
        ({"text.neq": "sometext"}, [2, 3, 4, 5, 6, 7, 8]),
        ({"text.eq": "somet"}, []),
        ({"text.gte": "a"}, [1]),
        ({"text.gte": "somet"}, [1]),
        ({"text.gte": "sometext"}, [1]),
        ({"text.lt": "somet"}, []),
        ({"data.data2.data3": 2, "data.data2.data4": None}, [2]),
        ({"data.data2.data3": 2, "data.data2.data4": 5}, []),
        ({"data.data2.data3": 4}, [4]),
        ({"data.data2.data3": [3, 4, "e"]}, [3, 4]),
        ({"data.data2.data3": None}, [8]),
        ({"data.data2": "4"}, []),
        ({"list.0.a": 1}, [1, 6]),
        ({"list2": 1}, [2]),
        ({"list2": [1, 5]}, [2]),
        ({"list2": [1, 2]}, [2]),
        ({"list2": [5, 7]}, []),
        ({"list.ANYINDEX.a": 1}, [1]),
        ({"list.a": 3, "list.b": 1}, [8]),
        ({"list.ANYINDEX.a": 3, "list.ANYINDEX.b": 1}, []),
        ({"list.ANYINDEX.a": 3, "list.ANYINDEX.c.a": 3}, [8]),
        ({"list.ANYINDEX.a": 3, "list.ANYINDEX.b": 0}, [8]),
        (
            {
                "list.ANYINDEX.a": 3,
                "list.ANYINDEX.c.ANYINDEX.a": 0,
                "list.ANYINDEX.c.ANYINDEX.b": "v",
            },
            [8],
        ),
        (
            {
                "list.ANYINDEX.a": 3,
                "list.ANYINDEX.c.ANYINDEX.a": 0,
                "list.ANYINDEX.c.ANYINDEX.b": 1,
            },
            [],
        ),
        ({"list.c.b": 1}, [8]),
        ({"list.c.b": None}, [1, 2, 3, 4, 5, 6, 7]),
        # ({"data.data2.data3": 4}, []),
        # ({"data.data2.data3": 4}, []),
    ],
)
def test_get_list(db_memory_with_many_data, db_filter, expected_ids):
    result = db_memory_with_many_data.get_list("test", db_filter)
    assert isinstance(result, list)
    result_ids = [item["_id"] for item in result]
    assert len(result) == len(
        expected_ids
    ), "for db_filter={} result={} expected_ids={}".format(
        db_filter, result, result_ids
    )
    assert result_ids == expected_ids
    for i in range(len(result)):
        assert result[i] in db_memory_with_many_data.db["test"]

    assert len(db_memory_with_many_data.db) == 1
    assert "test" in db_memory_with_many_data.db
    assert len(db_memory_with_many_data.db["test"]) == 8
    result = db_memory_with_many_data.count("test", db_filter)
    assert result == len(expected_ids)


@pytest.mark.parametrize(
    "table, db_filter, expected_data", [("test", {}, {"_id": 1, "data": 1})]
)
def test_get_one_with_multiple_results(
    db_memory_with_data, table, db_filter, expected_data
):
    result = db_memory_with_data.get_one(table, db_filter, fail_on_more=False)
    assert result == expected_data
    assert len(db_memory_with_data.db) == 1
    assert table in db_memory_with_data.db
    assert len(db_memory_with_data.db[table]) == 3
    assert result in db_memory_with_data.db[table]


def test_get_one_with_multiple_results_exception(db_memory_with_data):
    table = "test"
    db_filter = {}
    with pytest.raises(DbException) as excinfo:
        db_memory_with_data.get_one(table, db_filter)
    assert str(excinfo.value) == (
        empty_exception_message() + get_one_multiple_exception_message(db_filter)
    )
    # assert excinfo.value.http_code == http.HTTPStatus.CONFLICT


@pytest.mark.parametrize(
    "table, db_filter",
    [
        ("test", {"_id": 4}),
        ("test", {"data": 4}),
        ("test", {"_id": 4, "data": 4}),
        ("test_table", {"_id": 4}),
        ("test_table", {"data": 4}),
        ("test_table", {"_id": 4, "data": 4}),
    ],
)
def test_get_one_with_non_empty_db_exception(db_memory_with_data, table, db_filter):
    with pytest.raises(DbException) as excinfo:
        db_memory_with_data.get_one(table, db_filter)
    assert str(excinfo.value) == (
        empty_exception_message() + get_one_exception_message(db_filter)
    )
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


@pytest.mark.parametrize(
    "table, db_filter",
    [
        ("test", {"_id": 4}),
        ("test", {"data": 4}),
        ("test", {"_id": 4, "data": 4}),
        ("test_table", {"_id": 4}),
        ("test_table", {"data": 4}),
        ("test_table", {"_id": 4, "data": 4}),
    ],
)
def test_get_one_with_non_empty_db_none(db_memory_with_data, table, db_filter):
    result = db_memory_with_data.get_one(table, db_filter, fail_on_empty=False)
    assert result is None


@pytest.mark.parametrize(
    "table, db_filter",
    [
        ("test", {"_id": 4}),
        ("test", {"data": 4}),
        ("test", {"_id": 4, "data": 4}),
        ("test_table", {"_id": 4}),
        ("test_table", {"data": 4}),
        ("test_table", {"_id": 4, "data": 4}),
    ],
)
def test_get_one_with_empty_db_exception(db_memory, table, db_filter):
    with pytest.raises(DbException) as excinfo:
        db_memory.get_one(table, db_filter)
    assert str(excinfo.value) == (
        empty_exception_message() + get_one_exception_message(db_filter)
    )
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


@pytest.mark.parametrize(
    "table, db_filter",
    [
        ("test", {"_id": 4}),
        ("test", {"data": 4}),
        ("test", {"_id": 4, "data": 4}),
        ("test_table", {"_id": 4}),
        ("test_table", {"data": 4}),
        ("test_table", {"_id": 4, "data": 4}),
    ],
)
def test_get_one_with_empty_db_none(db_memory, table, db_filter):
    result = db_memory.get_one(table, db_filter, fail_on_empty=False)
    assert result is None


def test_get_one_generic_exception(db_memory_with_data):
    table = "test"
    db_filter = {}
    db_memory_with_data._find = MagicMock(side_effect=Exception())
    with pytest.raises(DbException) as excinfo:
        db_memory_with_data.get_one(table, db_filter)
    assert str(excinfo.value) == empty_exception_message()
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


@pytest.mark.parametrize(
    "table, db_filter, expected_data",
    [
        ("test", {}, []),
        ("test", {"_id": 1}, [{"_id": 2, "data": 2}, {"_id": 3, "data": 3}]),
        ("test", {"_id": 2}, [{"_id": 1, "data": 1}, {"_id": 3, "data": 3}]),
        ("test", {"_id": 1, "data": 1}, [{"_id": 2, "data": 2}, {"_id": 3, "data": 3}]),
        ("test", {"_id": 2, "data": 2}, [{"_id": 1, "data": 1}, {"_id": 3, "data": 3}]),
    ],
)
def test_del_list_with_non_empty_db(
    db_memory_with_data, table, db_filter, expected_data
):
    result = db_memory_with_data.del_list(table, db_filter)
    assert result["deleted"] == (3 - len(expected_data))
    assert len(db_memory_with_data.db) == 1
    assert table in db_memory_with_data.db
    assert len(db_memory_with_data.db[table]) == len(expected_data)
    for data in expected_data:
        assert data in db_memory_with_data.db[table]


@pytest.mark.parametrize(
    "table, db_filter",
    [
        ("test", {}),
        ("test", {"_id": 1}),
        ("test", {"_id": 2}),
        ("test", {"data": 1}),
        ("test", {"data": 2}),
        ("test", {"_id": 1, "data": 1}),
        ("test", {"_id": 2, "data": 2}),
    ],
)
def test_del_list_with_empty_db(db_memory, table, db_filter):
    result = db_memory.del_list(table, db_filter)
    assert result["deleted"] == 0


def test_del_list_generic_exception(db_memory_with_data):
    table = "test"
    db_filter = {}
    db_memory_with_data._find = MagicMock(side_effect=Exception())
    with pytest.raises(DbException) as excinfo:
        db_memory_with_data.del_list(table, db_filter)
    assert str(excinfo.value) == empty_exception_message()
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


@pytest.mark.parametrize(
    "table, db_filter, data",
    [
        ("test", {}, {"_id": 1, "data": 1}),
        ("test", {"_id": 1}, {"_id": 1, "data": 1}),
        ("test", {"data": 1}, {"_id": 1, "data": 1}),
        ("test", {"_id": 1, "data": 1}, {"_id": 1, "data": 1}),
        ("test", {"_id": 2}, {"_id": 2, "data": 2}),
        ("test", {"data": 2}, {"_id": 2, "data": 2}),
        ("test", {"_id": 2, "data": 2}, {"_id": 2, "data": 2}),
    ],
)
def test_del_one(db_memory_with_data, table, db_filter, data):
    result = db_memory_with_data.del_one(table, db_filter)
    assert result == {"deleted": 1}
    assert len(db_memory_with_data.db) == 1
    assert table in db_memory_with_data.db
    assert len(db_memory_with_data.db[table]) == 2
    assert data not in db_memory_with_data.db[table]


@pytest.mark.parametrize(
    "table, db_filter",
    [
        ("test", {}),
        ("test", {"_id": 1}),
        ("test", {"_id": 2}),
        ("test", {"data": 1}),
        ("test", {"data": 2}),
        ("test", {"_id": 1, "data": 1}),
        ("test", {"_id": 2, "data": 2}),
        ("test_table", {}),
        ("test_table", {"_id": 1}),
        ("test_table", {"_id": 2}),
        ("test_table", {"data": 1}),
        ("test_table", {"data": 2}),
        ("test_table", {"_id": 1, "data": 1}),
        ("test_table", {"_id": 2, "data": 2}),
    ],
)
def test_del_one_with_empty_db_exception(db_memory, table, db_filter):
    with pytest.raises(DbException) as excinfo:
        db_memory.del_one(table, db_filter)
    assert str(excinfo.value) == (
        empty_exception_message() + del_one_exception_message(db_filter)
    )
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


@pytest.mark.parametrize(
    "table, db_filter",
    [
        ("test", {}),
        ("test", {"_id": 1}),
        ("test", {"_id": 2}),
        ("test", {"data": 1}),
        ("test", {"data": 2}),
        ("test", {"_id": 1, "data": 1}),
        ("test", {"_id": 2, "data": 2}),
        ("test_table", {}),
        ("test_table", {"_id": 1}),
        ("test_table", {"_id": 2}),
        ("test_table", {"data": 1}),
        ("test_table", {"data": 2}),
        ("test_table", {"_id": 1, "data": 1}),
        ("test_table", {"_id": 2, "data": 2}),
    ],
)
def test_del_one_with_empty_db_none(db_memory, table, db_filter):
    result = db_memory.del_one(table, db_filter, fail_on_empty=False)
    assert result is None


@pytest.mark.parametrize(
    "table, db_filter",
    [
        ("test", {"_id": 4}),
        ("test", {"_id": 5}),
        ("test", {"data": 4}),
        ("test", {"data": 5}),
        ("test", {"_id": 1, "data": 2}),
        ("test", {"_id": 2, "data": 3}),
        ("test_table", {}),
        ("test_table", {"_id": 1}),
        ("test_table", {"_id": 2}),
        ("test_table", {"data": 1}),
        ("test_table", {"data": 2}),
        ("test_table", {"_id": 1, "data": 1}),
        ("test_table", {"_id": 2, "data": 2}),
    ],
)
def test_del_one_with_non_empty_db_exception(db_memory_with_data, table, db_filter):
    with pytest.raises(DbException) as excinfo:
        db_memory_with_data.del_one(table, db_filter)
    assert str(excinfo.value) == (
        empty_exception_message() + del_one_exception_message(db_filter)
    )
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


@pytest.mark.parametrize(
    "table, db_filter",
    [
        ("test", {"_id": 4}),
        ("test", {"_id": 5}),
        ("test", {"data": 4}),
        ("test", {"data": 5}),
        ("test", {"_id": 1, "data": 2}),
        ("test", {"_id": 2, "data": 3}),
        ("test_table", {}),
        ("test_table", {"_id": 1}),
        ("test_table", {"_id": 2}),
        ("test_table", {"data": 1}),
        ("test_table", {"data": 2}),
        ("test_table", {"_id": 1, "data": 1}),
        ("test_table", {"_id": 2, "data": 2}),
    ],
)
def test_del_one_with_non_empty_db_none(db_memory_with_data, table, db_filter):
    result = db_memory_with_data.del_one(table, db_filter, fail_on_empty=False)
    assert result is None


@pytest.mark.parametrize("fail_on_empty", [(True), (False)])
def test_del_one_generic_exception(db_memory_with_data, fail_on_empty):
    table = "test"
    db_filter = {}
    db_memory_with_data._find = MagicMock(side_effect=Exception())
    with pytest.raises(DbException) as excinfo:
        db_memory_with_data.del_one(table, db_filter, fail_on_empty=fail_on_empty)
    assert str(excinfo.value) == empty_exception_message()
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


@pytest.mark.parametrize(
    "table, _id, indata",
    [
        ("test", 1, {"_id": 1, "data": 42}),
        ("test", 1, {"_id": 1, "data": 42, "kk": 34}),
        ("test", 1, {"_id": 1}),
        ("test", 2, {"_id": 2, "data": 42}),
        ("test", 2, {"_id": 2, "data": 42, "kk": 34}),
        ("test", 2, {"_id": 2}),
        ("test", 3, {"_id": 3, "data": 42}),
        ("test", 3, {"_id": 3, "data": 42, "kk": 34}),
        ("test", 3, {"_id": 3}),
    ],
)
def test_replace(db_memory_with_data, table, _id, indata):
    result = db_memory_with_data.replace(table, _id, indata)
    assert result == {"updated": 1}
    assert len(db_memory_with_data.db) == 1
    assert table in db_memory_with_data.db
    assert len(db_memory_with_data.db[table]) == 3
    assert indata in db_memory_with_data.db[table]


@pytest.mark.parametrize(
    "table, _id, indata",
    [
        ("test", 1, {"_id": 1, "data": 42}),
        ("test", 2, {"_id": 2}),
        ("test", 3, {"_id": 3}),
    ],
)
def test_replace_without_data_exception(db_memory, table, _id, indata):
    with pytest.raises(DbException) as excinfo:
        db_memory.replace(table, _id, indata, fail_on_empty=True)
    assert str(excinfo.value) == (replace_exception_message(_id))
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


@pytest.mark.parametrize(
    "table, _id, indata",
    [
        ("test", 1, {"_id": 1, "data": 42}),
        ("test", 2, {"_id": 2}),
        ("test", 3, {"_id": 3}),
    ],
)
def test_replace_without_data_none(db_memory, table, _id, indata):
    result = db_memory.replace(table, _id, indata, fail_on_empty=False)
    assert result is None


@pytest.mark.parametrize(
    "table, _id, indata",
    [
        ("test", 11, {"_id": 11, "data": 42}),
        ("test", 12, {"_id": 12}),
        ("test", 33, {"_id": 33}),
    ],
)
def test_replace_with_data_exception(db_memory_with_data, table, _id, indata):
    with pytest.raises(DbException) as excinfo:
        db_memory_with_data.replace(table, _id, indata, fail_on_empty=True)
    assert str(excinfo.value) == (replace_exception_message(_id))
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


@pytest.mark.parametrize(
    "table, _id, indata",
    [
        ("test", 11, {"_id": 11, "data": 42}),
        ("test", 12, {"_id": 12}),
        ("test", 33, {"_id": 33}),
    ],
)
def test_replace_with_data_none(db_memory_with_data, table, _id, indata):
    result = db_memory_with_data.replace(table, _id, indata, fail_on_empty=False)
    assert result is None


@pytest.mark.parametrize("fail_on_empty", [True, False])
def test_replace_generic_exception(db_memory_with_data, fail_on_empty):
    table = "test"
    _id = {}
    indata = {"_id": 1, "data": 1}
    db_memory_with_data._find = MagicMock(side_effect=Exception())
    with pytest.raises(DbException) as excinfo:
        db_memory_with_data.replace(table, _id, indata, fail_on_empty=fail_on_empty)
    assert str(excinfo.value) == empty_exception_message()
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


@pytest.mark.parametrize(
    "table, id, data",
    [
        ("test", "1", {"data": 1}),
        ("test", "1", {"data": 2}),
        ("test", "2", {"data": 1}),
        ("test", "2", {"data": 2}),
        ("test_table", "1", {"data": 1}),
        ("test_table", "1", {"data": 2}),
        ("test_table", "2", {"data": 1}),
        ("test_table", "2", {"data": 2}),
        ("test", "1", {"data_1": 1, "data_2": 2}),
        ("test", "1", {"data_1": 2, "data_2": 1}),
        ("test", "2", {"data_1": 1, "data_2": 2}),
        ("test", "2", {"data_1": 2, "data_2": 1}),
        ("test_table", "1", {"data_1": 1, "data_2": 2}),
        ("test_table", "1", {"data_1": 2, "data_2": 1}),
        ("test_table", "2", {"data_1": 1, "data_2": 2}),
        ("test_table", "2", {"data_1": 2, "data_2": 1}),
    ],
)
def test_create_with_empty_db_with_id(db_memory, table, id, data):
    data_to_insert = data
    data_to_insert["_id"] = id
    returned_id = db_memory.create(table, data_to_insert)
    assert returned_id == id
    assert len(db_memory.db) == 1
    assert table in db_memory.db
    assert len(db_memory.db[table]) == 1
    assert data_to_insert in db_memory.db[table]


@pytest.mark.parametrize(
    "table, id, data",
    [
        ("test", "4", {"data": 1}),
        ("test", "5", {"data": 2}),
        ("test", "4", {"data": 1}),
        ("test", "5", {"data": 2}),
        ("test_table", "4", {"data": 1}),
        ("test_table", "5", {"data": 2}),
        ("test_table", "4", {"data": 1}),
        ("test_table", "5", {"data": 2}),
        ("test", "4", {"data_1": 1, "data_2": 2}),
        ("test", "5", {"data_1": 2, "data_2": 1}),
        ("test", "4", {"data_1": 1, "data_2": 2}),
        ("test", "5", {"data_1": 2, "data_2": 1}),
        ("test_table", "4", {"data_1": 1, "data_2": 2}),
        ("test_table", "5", {"data_1": 2, "data_2": 1}),
        ("test_table", "4", {"data_1": 1, "data_2": 2}),
        ("test_table", "5", {"data_1": 2, "data_2": 1}),
    ],
)
def test_create_with_non_empty_db_with_id(db_memory_with_data, table, id, data):
    data_to_insert = data
    data_to_insert["_id"] = id
    returned_id = db_memory_with_data.create(table, data_to_insert)
    assert returned_id == id
    assert len(db_memory_with_data.db) == (1 if table == "test" else 2)
    assert table in db_memory_with_data.db
    assert len(db_memory_with_data.db[table]) == (4 if table == "test" else 1)
    assert data_to_insert in db_memory_with_data.db[table]


@pytest.mark.parametrize(
    "table, data",
    [
        ("test", {"data": 1}),
        ("test", {"data": 2}),
        ("test", {"data": 1}),
        ("test", {"data": 2}),
        ("test_table", {"data": 1}),
        ("test_table", {"data": 2}),
        ("test_table", {"data": 1}),
        ("test_table", {"data": 2}),
        ("test", {"data_1": 1, "data_2": 2}),
        ("test", {"data_1": 2, "data_2": 1}),
        ("test", {"data_1": 1, "data_2": 2}),
        ("test", {"data_1": 2, "data_2": 1}),
        ("test_table", {"data_1": 1, "data_2": 2}),
        ("test_table", {"data_1": 2, "data_2": 1}),
        ("test_table", {"data_1": 1, "data_2": 2}),
        ("test_table", {"data_1": 2, "data_2": 1}),
    ],
)
def test_create_with_empty_db_without_id(db_memory, table, data):
    returned_id = db_memory.create(table, data)
    assert len(db_memory.db) == 1
    assert table in db_memory.db
    assert len(db_memory.db[table]) == 1
    data_inserted = data
    data_inserted["_id"] = returned_id
    assert data_inserted in db_memory.db[table]


@pytest.mark.parametrize(
    "table, data",
    [
        ("test", {"data": 1}),
        ("test", {"data": 2}),
        ("test", {"data": 1}),
        ("test", {"data": 2}),
        ("test_table", {"data": 1}),
        ("test_table", {"data": 2}),
        ("test_table", {"data": 1}),
        ("test_table", {"data": 2}),
        ("test", {"data_1": 1, "data_2": 2}),
        ("test", {"data_1": 2, "data_2": 1}),
        ("test", {"data_1": 1, "data_2": 2}),
        ("test", {"data_1": 2, "data_2": 1}),
        ("test_table", {"data_1": 1, "data_2": 2}),
        ("test_table", {"data_1": 2, "data_2": 1}),
        ("test_table", {"data_1": 1, "data_2": 2}),
        ("test_table", {"data_1": 2, "data_2": 1}),
    ],
)
def test_create_with_non_empty_db_without_id(db_memory_with_data, table, data):
    returned_id = db_memory_with_data.create(table, data)
    assert len(db_memory_with_data.db) == (1 if table == "test" else 2)
    assert table in db_memory_with_data.db
    assert len(db_memory_with_data.db[table]) == (4 if table == "test" else 1)
    data_inserted = data
    data_inserted["_id"] = returned_id
    assert data_inserted in db_memory_with_data.db[table]


def test_create_with_exception(db_memory):
    table = "test"
    data = {"_id": 1, "data": 1}
    db_memory.db = MagicMock()
    db_memory.db.__contains__.side_effect = Exception()
    with pytest.raises(DbException) as excinfo:
        db_memory.create(table, data)
    assert str(excinfo.value) == empty_exception_message()
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


@pytest.mark.parametrize(
    "db_content, update_dict, expected, message",
    [
        (
            {"a": {"none": None}},
            {"a.b.num": "v"},
            {"a": {"none": None, "b": {"num": "v"}}},
            "create dict",
        ),
        (
            {"a": {"none": None}},
            {"a.none.num": "v"},
            {"a": {"none": {"num": "v"}}},
            "create dict over none",
        ),
        (
            {"a": {"b": {"num": 4}}},
            {"a.b.num": "v"},
            {"a": {"b": {"num": "v"}}},
            "replace_number",
        ),
        (
            {"a": {"b": {"num": 4}}},
            {"a.b.num.c.d": "v"},
            None,
            "create dict over number should fail",
        ),
        (
            {"a": {"b": {"num": 4}}},
            {"a.b": "v"},
            {"a": {"b": "v"}},
            "replace dict with a string",
        ),
        (
            {"a": {"b": {"num": 4}}},
            {"a.b": None},
            {"a": {"b": None}},
            "replace dict with None",
        ),
        (
            {"a": [{"b": {"num": 4}}]},
            {"a.b.num": "v"},
            None,
            "create dict over list should fail",
        ),
        (
            {"a": [{"b": {"num": 4}}]},
            {"a.0.b.num": "v"},
            {"a": [{"b": {"num": "v"}}]},
            "set list",
        ),
        (
            {"a": [{"b": {"num": 4}}]},
            {"a.3.b.num": "v"},
            {"a": [{"b": {"num": 4}}, None, None, {"b": {"num": "v"}}]},
            "expand list",
        ),
        ({"a": [[4]]}, {"a.0.0": "v"}, {"a": [["v"]]}, "set nested list"),
        ({"a": [[4]]}, {"a.0.2": "v"}, {"a": [[4, None, "v"]]}, "expand nested list"),
        (
            {"a": [[4]]},
            {"a.2.2": "v"},
            {"a": [[4], None, {"2": "v"}]},
            "expand list and add number key",
        ),
    ],
)
def test_set_one(db_memory, db_content, update_dict, expected, message):
    db_memory._find = Mock(return_value=((0, db_content),))
    if expected is None:
        with pytest.raises(DbException) as excinfo:
            db_memory.set_one("table", {}, update_dict)
        assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND, message
    else:
        db_memory.set_one("table", {}, update_dict)
        assert db_content == expected, message


class TestDbMemory(unittest.TestCase):
    # TODO to delete. This is cover with pytest test_set_one.
    def test_set_one(self):
        test_set = (
            # (database content, set-content, expected database content (None=fails), message)
            (
                {"a": {"none": None}},
                {"a.b.num": "v"},
                {"a": {"none": None, "b": {"num": "v"}}},
                "create dict",
            ),
            (
                {"a": {"none": None}},
                {"a.none.num": "v"},
                {"a": {"none": {"num": "v"}}},
                "create dict over none",
            ),
            (
                {"a": {"b": {"num": 4}}},
                {"a.b.num": "v"},
                {"a": {"b": {"num": "v"}}},
                "replace_number",
            ),
            (
                {"a": {"b": {"num": 4}}},
                {"a.b.num.c.d": "v"},
                None,
                "create dict over number should fail",
            ),
            (
                {"a": {"b": {"num": 4}}},
                {"a.b": "v"},
                {"a": {"b": "v"}},
                "replace dict with a string",
            ),
            (
                {"a": {"b": {"num": 4}}},
                {"a.b": None},
                {"a": {"b": None}},
                "replace dict with None",
            ),
            (
                {"a": [{"b": {"num": 4}}]},
                {"a.b.num": "v"},
                None,
                "create dict over list should fail",
            ),
            (
                {"a": [{"b": {"num": 4}}]},
                {"a.0.b.num": "v"},
                {"a": [{"b": {"num": "v"}}]},
                "set list",
            ),
            (
                {"a": [{"b": {"num": 4}}]},
                {"a.3.b.num": "v"},
                {"a": [{"b": {"num": 4}}, None, None, {"b": {"num": "v"}}]},
                "expand list",
            ),
            ({"a": [[4]]}, {"a.0.0": "v"}, {"a": [["v"]]}, "set nested list"),
            (
                {"a": [[4]]},
                {"a.0.2": "v"},
                {"a": [[4, None, "v"]]},
                "expand nested list",
            ),
            (
                {"a": [[4]]},
                {"a.2.2": "v"},
                {"a": [[4], None, {"2": "v"}]},
                "expand list and add number key",
            ),
            ({"a": None}, {"b.c": "v"}, {"a": None, "b": {"c": "v"}}, "expand at root"),
        )
        db_men = DbMemory()
        db_men._find = Mock()
        for db_content, update_dict, expected, message in test_set:
            db_men._find.return_value = ((0, db_content),)
            if expected is None:
                self.assertRaises(DbException, db_men.set_one, "table", {}, update_dict)
            else:
                db_men.set_one("table", {}, update_dict)
                self.assertEqual(db_content, expected, message)

    def test_set_one_pull(self):
        example = {"a": [1, "1", 1], "d": {}, "n": None}
        test_set = (
            # (database content, set-content, expected database content (None=fails), message)
            (example, {"a": "1"}, {"a": [1, 1], "d": {}, "n": None}, "pull one item"),
            (example, {"a": 1}, {"a": ["1"], "d": {}, "n": None}, "pull two items"),
            (example, {"a": "v"}, example, "pull non existing item"),
            (example, {"a.6": 1}, example, "pull non existing arrray"),
            (example, {"d.b.c": 1}, example, "pull non existing arrray2"),
            (example, {"b": 1}, example, "pull non existing arrray3"),
            (example, {"d": 1}, None, "pull over dict"),
            (example, {"n": 1}, None, "pull over None"),
        )
        db_men = DbMemory()
        db_men._find = Mock()
        for db_content, pull_dict, expected, message in test_set:
            db_content = deepcopy(db_content)
            db_men._find.return_value = ((0, db_content),)
            if expected is None:
                self.assertRaises(
                    DbException,
                    db_men.set_one,
                    "table",
                    {},
                    None,
                    fail_on_empty=False,
                    pull=pull_dict,
                )
            else:
                db_men.set_one("table", {}, None, pull=pull_dict)
                self.assertEqual(db_content, expected, message)

    def test_set_one_push(self):
        example = {"a": [1, "1", 1], "d": {}, "n": None}
        test_set = (
            # (database content, set-content, expected database content (None=fails), message)
            (
                example,
                {"d.b.c": 1},
                {"a": [1, "1", 1], "d": {"b": {"c": [1]}}, "n": None},
                "push non existing arrray2",
            ),
            (
                example,
                {"b": 1},
                {"a": [1, "1", 1], "d": {}, "b": [1], "n": None},
                "push non existing arrray3",
            ),
            (
                example,
                {"a.6": 1},
                {"a": [1, "1", 1, None, None, None, [1]], "d": {}, "n": None},
                "push non existing arrray",
            ),
            (
                example,
                {"a": 2},
                {"a": [1, "1", 1, 2], "d": {}, "n": None},
                "push one item",
            ),
            (
                example,
                {"a": {1: 1}},
                {"a": [1, "1", 1, {1: 1}], "d": {}, "n": None},
                "push a dict",
            ),
            (example, {"d": 1}, None, "push over dict"),
            (example, {"n": 1}, None, "push over None"),
        )
        db_men = DbMemory()
        db_men._find = Mock()
        for db_content, push_dict, expected, message in test_set:
            db_content = deepcopy(db_content)
            db_men._find.return_value = ((0, db_content),)
            if expected is None:
                self.assertRaises(
                    DbException,
                    db_men.set_one,
                    "table",
                    {},
                    None,
                    fail_on_empty=False,
                    push=push_dict,
                )
            else:
                db_men.set_one("table", {}, None, push=push_dict)
                self.assertEqual(db_content, expected, message)

    def test_set_one_push_list(self):
        example = {"a": [1, "1", 1], "d": {}, "n": None}
        test_set = (
            # (database content, set-content, expected database content (None=fails), message)
            (
                example,
                {"d.b.c": [1]},
                {"a": [1, "1", 1], "d": {"b": {"c": [1]}}, "n": None},
                "push non existing arrray2",
            ),
            (
                example,
                {"b": [1]},
                {"a": [1, "1", 1], "d": {}, "b": [1], "n": None},
                "push non existing arrray3",
            ),
            (
                example,
                {"a.6": [1]},
                {"a": [1, "1", 1, None, None, None, [1]], "d": {}, "n": None},
                "push non existing arrray",
            ),
            (
                example,
                {"a": [2, 3]},
                {"a": [1, "1", 1, 2, 3], "d": {}, "n": None},
                "push two item",
            ),
            (
                example,
                {"a": [{1: 1}]},
                {"a": [1, "1", 1, {1: 1}], "d": {}, "n": None},
                "push a dict",
            ),
            (example, {"d": [1]}, None, "push over dict"),
            (example, {"n": [1]}, None, "push over None"),
            (example, {"a": 1}, None, "invalid push list non an array"),
        )
        db_men = DbMemory()
        db_men._find = Mock()
        for db_content, push_list, expected, message in test_set:
            db_content = deepcopy(db_content)
            db_men._find.return_value = ((0, db_content),)
            if expected is None:
                self.assertRaises(
                    DbException,
                    db_men.set_one,
                    "table",
                    {},
                    None,
                    fail_on_empty=False,
                    push_list=push_list,
                )
            else:
                db_men.set_one("table", {}, None, push_list=push_list)
                self.assertEqual(db_content, expected, message)

    def test_unset_one(self):
        example = {"a": [1, "1", 1], "d": {}, "n": None}
        test_set = (
            # (database content, set-content, expected database content (None=fails), message)
            (example, {"d.b.c": 1}, example, "unset non existing"),
            (example, {"b": 1}, example, "unset non existing"),
            (example, {"a.6": 1}, example, "unset non existing arrray"),
            (example, {"a": 2}, {"d": {}, "n": None}, "unset array"),
            (example, {"d": 1}, {"a": [1, "1", 1], "n": None}, "unset dict"),
            (example, {"n": 1}, {"a": [1, "1", 1], "d": {}}, "unset None"),
        )
        db_men = DbMemory()
        db_men._find = Mock()
        for db_content, unset_dict, expected, message in test_set:
            db_content = deepcopy(db_content)
            db_men._find.return_value = ((0, db_content),)
            if expected is None:
                self.assertRaises(
                    DbException,
                    db_men.set_one,
                    "table",
                    {},
                    None,
                    fail_on_empty=False,
                    unset=unset_dict,
                )
            else:
                db_men.set_one("table", {}, None, unset=unset_dict)
                self.assertEqual(db_content, expected, message)
