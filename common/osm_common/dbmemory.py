# -*- coding: utf-8 -*-

# Copyright 2018 Telefonica S.A.
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

from copy import deepcopy
from http import HTTPStatus
import logging
from uuid import uuid4

from osm_common.dbbase import DbBase, DbException
from osm_common.dbmongo import deep_update


__author__ = "Alfonso Tierno <alfonso.tiernosepulveda@telefonica.com>"


class DbMemory(DbBase):
    def __init__(self, logger_name="db", lock=False):
        super().__init__(logger_name=logger_name, lock=lock)
        self.db = {}

    def db_connect(self, config):
        """
        Connect to database
        :param config: Configuration of database
        :return: None or raises DbException on error
        """
        if "logger_name" in config:
            self.logger = logging.getLogger(config["logger_name"])
        master_key = config.get("commonkey") or config.get("masterpassword")
        if master_key:
            self.set_secret_key(master_key)

    @staticmethod
    def _format_filter(q_filter):
        db_filter = {}
        # split keys with ANYINDEX in this way:
        # {"A.B.ANYINDEX.C.D.ANYINDEX.E": v }  -> {"A.B.ANYINDEX": {"C.D.ANYINDEX": {"E": v}}}
        if q_filter:
            for k, v in q_filter.items():
                db_v = v
                kleft, _, kright = k.rpartition(".ANYINDEX.")
                while kleft:
                    k = kleft + ".ANYINDEX"
                    db_v = {kright: db_v}
                    kleft, _, kright = k.rpartition(".ANYINDEX.")
                deep_update(db_filter, {k: db_v})

        return db_filter

    def _find(self, table, q_filter):
        def recursive_find(key_list, key_next_index, content, oper, target):
            if key_next_index == len(key_list) or content is None:
                try:
                    if oper in ("eq", "cont"):
                        if isinstance(target, list):
                            if isinstance(content, list):
                                return any(
                                    content_item in target for content_item in content
                                )
                            return content in target
                        elif isinstance(content, list):
                            return target in content
                        else:
                            return content == target
                    elif oper in ("neq", "ne", "ncont"):
                        if isinstance(target, list):
                            if isinstance(content, list):
                                return all(
                                    content_item not in target
                                    for content_item in content
                                )
                            return content not in target
                        elif isinstance(content, list):
                            return target not in content
                        else:
                            return content != target
                    if oper == "gt":
                        return content > target
                    elif oper == "gte":
                        return content >= target
                    elif oper == "lt":
                        return content < target
                    elif oper == "lte":
                        return content <= target
                    else:
                        raise DbException(
                            "Unknown filter operator '{}' in key '{}'".format(
                                oper, ".".join(key_list)
                            ),
                            http_code=HTTPStatus.BAD_REQUEST,
                        )
                except TypeError:
                    return False

            elif isinstance(content, dict):
                return recursive_find(
                    key_list,
                    key_next_index + 1,
                    content.get(key_list[key_next_index]),
                    oper,
                    target,
                )
            elif isinstance(content, list):
                look_for_match = True  # when there is a match return immediately
                if (target is None) != (
                    oper in ("neq", "ne", "ncont")
                ):  # one True and other False (Xor)
                    look_for_match = (
                        False  # when there is not a match return immediately
                    )

                for content_item in content:
                    if key_list[key_next_index] == "ANYINDEX" and isinstance(v, dict):
                        matches = True
                        if target:
                            for k2, v2 in target.items():
                                k_new_list = k2.split(".")
                                new_operator = "eq"
                                if k_new_list[-1] in (
                                    "eq",
                                    "ne",
                                    "gt",
                                    "gte",
                                    "lt",
                                    "lte",
                                    "cont",
                                    "ncont",
                                    "neq",
                                ):
                                    new_operator = k_new_list.pop()
                                if not recursive_find(
                                    k_new_list, 0, content_item, new_operator, v2
                                ):
                                    matches = False
                                    break

                    else:
                        matches = recursive_find(
                            key_list, key_next_index, content_item, oper, target
                        )
                    if matches == look_for_match:
                        return matches
                if key_list[key_next_index].isdecimal() and int(
                    key_list[key_next_index]
                ) < len(content):
                    matches = recursive_find(
                        key_list,
                        key_next_index + 1,
                        content[int(key_list[key_next_index])],
                        oper,
                        target,
                    )
                    if matches == look_for_match:
                        return matches
                return not look_for_match
            else:  # content is not dict, nor list neither None, so not found
                if oper in ("neq", "ne", "ncont"):
                    return target is not None
                else:
                    return target is None

        for i, row in enumerate(self.db.get(table, ())):
            q_filter = q_filter or {}
            for k, v in q_filter.items():
                k_list = k.split(".")
                operator = "eq"
                if k_list[-1] in (
                    "eq",
                    "ne",
                    "gt",
                    "gte",
                    "lt",
                    "lte",
                    "cont",
                    "ncont",
                    "neq",
                ):
                    operator = k_list.pop()
                matches = recursive_find(k_list, 0, row, operator, v)
                if not matches:
                    break
            else:
                # match
                yield i, row

    def get_list(self, table, q_filter=None):
        """
        Obtain a list of entries matching q_filter
        :param table: collection or table
        :param q_filter: Filter
        :return: a list (can be empty) with the found entries. Raises DbException on error
        """
        try:
            result = []
            with self.lock:
                for _, row in self._find(table, self._format_filter(q_filter)):
                    result.append(deepcopy(row))
            return result
        except DbException:
            raise
        except Exception as e:  # TODO refine
            raise DbException(str(e))

    def count(self, table, q_filter=None):
        """
        Count the number of entries matching q_filter
        :param table: collection or table
        :param q_filter: Filter
        :return: number of entries found (can be zero)
        :raise: DbException on error
        """
        try:
            with self.lock:
                return sum(1 for x in self._find(table, self._format_filter(q_filter)))
        except DbException:
            raise
        except Exception as e:  # TODO refine
            raise DbException(str(e))

    def get_one(self, table, q_filter=None, fail_on_empty=True, fail_on_more=True):
        """
        Obtain one entry matching q_filter
        :param table: collection or table
        :param q_filter: Filter
        :param fail_on_empty: If nothing matches filter it returns None unless this flag is set tu True, in which case
        it raises a DbException
        :param fail_on_more: If more than one matches filter it returns one of then unless this flag is set tu True, so
        that it raises a DbException
        :return: The requested element, or None
        """
        try:
            result = None
            with self.lock:
                for _, row in self._find(table, self._format_filter(q_filter)):
                    if not fail_on_more:
                        return deepcopy(row)
                    if result:
                        raise DbException(
                            "Found more than one entry with filter='{}'".format(
                                q_filter
                            ),
                            HTTPStatus.CONFLICT.value,
                        )
                    result = row
            if not result and fail_on_empty:
                raise DbException(
                    "Not found entry with filter='{}'".format(q_filter),
                    HTTPStatus.NOT_FOUND,
                )
            return deepcopy(result)
        except Exception as e:  # TODO refine
            raise DbException(str(e))

    def del_list(self, table, q_filter=None):
        """
        Deletes all entries that match q_filter
        :param table: collection or table
        :param q_filter: Filter
        :return: Dict with the number of entries deleted
        """
        try:
            id_list = []
            with self.lock:
                for i, _ in self._find(table, self._format_filter(q_filter)):
                    id_list.append(i)
            deleted = len(id_list)
            for i in reversed(id_list):
                del self.db[table][i]
            return {"deleted": deleted}
        except DbException:
            raise
        except Exception as e:  # TODO refine
            raise DbException(str(e))

    def del_one(self, table, q_filter=None, fail_on_empty=True):
        """
        Deletes one entry that matches q_filter
        :param table: collection or table
        :param q_filter: Filter
        :param fail_on_empty: If nothing matches filter it returns '0' deleted unless this flag is set tu True, in
        which case it raises a DbException
        :return: Dict with the number of entries deleted
        """
        try:
            with self.lock:
                for i, _ in self._find(table, self._format_filter(q_filter)):
                    break
                else:
                    if fail_on_empty:
                        raise DbException(
                            "Not found entry with filter='{}'".format(q_filter),
                            HTTPStatus.NOT_FOUND,
                        )
                    return None
                del self.db[table][i]
            return {"deleted": 1}
        except Exception as e:  # TODO refine
            raise DbException(str(e))

    def _update(
        self,
        db_item,
        update_dict,
        unset=None,
        pull=None,
        push=None,
        push_list=None,
        pull_list=None,
    ):
        """
        Modifies an entry at database
        :param db_item: entry of the table to update
        :param update_dict: Plain dictionary with the content to be updated. It is a dot separated keys and a value
        :param unset: Plain dictionary with the content to be removed if exist. It is a dot separated keys, value is
                      ignored. If not exist, it is ignored
        :param pull: Plain dictionary with the content to be removed from an array. It is a dot separated keys and value
                     if exist in the array is removed. If not exist, it is ignored
        :param pull_list: Same as pull but values are arrays where each item is removed from the array
        :param push: Plain dictionary with the content to be appended to an array. It is a dot separated keys and value
                     is appended to the end of the array
        :param push_list: Same as push but values are arrays where each item is and appended instead of appending the
                          whole array
        :return: True if database has been changed, False if not; Exception on error
        """

        def _iterate_keys(k, db_nested, populate=True):
            k_list = k.split(".")
            k_item_prev = k_list[0]
            populated = False
            if k_item_prev not in db_nested and populate:
                populated = True
                db_nested[k_item_prev] = None
            for k_item in k_list[1:]:
                if isinstance(db_nested[k_item_prev], dict):
                    if k_item not in db_nested[k_item_prev]:
                        if not populate:
                            raise DbException(
                                "Cannot set '{}', not existing '{}'".format(k, k_item)
                            )
                        populated = True
                        db_nested[k_item_prev][k_item] = None
                elif isinstance(db_nested[k_item_prev], list) and k_item.isdigit():
                    # extend list with Nones if index greater than list
                    k_item = int(k_item)
                    if k_item >= len(db_nested[k_item_prev]):
                        if not populate:
                            raise DbException(
                                "Cannot set '{}', index too large '{}'".format(
                                    k, k_item
                                )
                            )
                        populated = True
                        db_nested[k_item_prev] += [None] * (
                            k_item - len(db_nested[k_item_prev]) + 1
                        )
                elif db_nested[k_item_prev] is None:
                    if not populate:
                        raise DbException(
                            "Cannot set '{}', not existing '{}'".format(k, k_item)
                        )
                    populated = True
                    db_nested[k_item_prev] = {k_item: None}
                else:  # number, string, boolean, ... or list but with not integer key
                    raise DbException(
                        "Cannot set '{}' on existing '{}={}'".format(
                            k, k_item_prev, db_nested[k_item_prev]
                        )
                    )
                db_nested = db_nested[k_item_prev]
                k_item_prev = k_item
            return db_nested, k_item_prev, populated

        updated = False
        try:
            if update_dict:
                for dot_k, v in update_dict.items():
                    dict_to_update, key_to_update, _ = _iterate_keys(dot_k, db_item)
                    dict_to_update[key_to_update] = v
                    updated = True
            if unset:
                for dot_k in unset:
                    try:
                        dict_to_update, key_to_update, _ = _iterate_keys(
                            dot_k, db_item, populate=False
                        )
                        del dict_to_update[key_to_update]
                        updated = True
                    except Exception as unset_error:
                        self.logger.error(f"{unset_error} occured while updating DB.")
            if pull:
                for dot_k, v in pull.items():
                    try:
                        dict_to_update, key_to_update, _ = _iterate_keys(
                            dot_k, db_item, populate=False
                        )
                    except Exception as pull_error:
                        self.logger.error(f"{pull_error} occured while updating DB.")
                        continue

                    if key_to_update not in dict_to_update:
                        continue
                    if not isinstance(dict_to_update[key_to_update], list):
                        raise DbException(
                            "Cannot pull '{}'. Target is not a list".format(dot_k)
                        )
                    while v in dict_to_update[key_to_update]:
                        dict_to_update[key_to_update].remove(v)
                        updated = True
            if pull_list:
                for dot_k, v in pull_list.items():
                    if not isinstance(v, list):
                        raise DbException(
                            "Invalid content at pull_list, '{}' must be an array".format(
                                dot_k
                            ),
                            http_code=HTTPStatus.BAD_REQUEST,
                        )
                    try:
                        dict_to_update, key_to_update, _ = _iterate_keys(
                            dot_k, db_item, populate=False
                        )
                    except Exception as iterate_error:
                        self.logger.error(
                            f"{iterate_error} occured while iterating keys in db update."
                        )
                        continue

                    if key_to_update not in dict_to_update:
                        continue
                    if not isinstance(dict_to_update[key_to_update], list):
                        raise DbException(
                            "Cannot pull_list '{}'. Target is not a list".format(dot_k)
                        )
                    for single_v in v:
                        while single_v in dict_to_update[key_to_update]:
                            dict_to_update[key_to_update].remove(single_v)
                            updated = True
            if push:
                for dot_k, v in push.items():
                    dict_to_update, key_to_update, populated = _iterate_keys(
                        dot_k, db_item
                    )
                    if (
                        isinstance(dict_to_update, dict)
                        and key_to_update not in dict_to_update
                    ):
                        dict_to_update[key_to_update] = [v]
                        updated = True
                    elif populated and dict_to_update[key_to_update] is None:
                        dict_to_update[key_to_update] = [v]
                        updated = True
                    elif not isinstance(dict_to_update[key_to_update], list):
                        raise DbException(
                            "Cannot push '{}'. Target is not a list".format(dot_k)
                        )
                    else:
                        dict_to_update[key_to_update].append(v)
                        updated = True
            if push_list:
                for dot_k, v in push_list.items():
                    if not isinstance(v, list):
                        raise DbException(
                            "Invalid content at push_list, '{}' must be an array".format(
                                dot_k
                            ),
                            http_code=HTTPStatus.BAD_REQUEST,
                        )
                    dict_to_update, key_to_update, populated = _iterate_keys(
                        dot_k, db_item
                    )
                    if (
                        isinstance(dict_to_update, dict)
                        and key_to_update not in dict_to_update
                    ):
                        dict_to_update[key_to_update] = v.copy()
                        updated = True
                    elif populated and dict_to_update[key_to_update] is None:
                        dict_to_update[key_to_update] = v.copy()
                        updated = True
                    elif not isinstance(dict_to_update[key_to_update], list):
                        raise DbException(
                            "Cannot push '{}'. Target is not a list".format(dot_k),
                            http_code=HTTPStatus.CONFLICT,
                        )
                    else:
                        dict_to_update[key_to_update] += v
                        updated = True

            return updated
        except DbException:
            raise
        except Exception as e:  # TODO refine
            raise DbException(str(e))

    def set_one(
        self,
        table,
        q_filter,
        update_dict,
        fail_on_empty=True,
        unset=None,
        pull=None,
        push=None,
        push_list=None,
        pull_list=None,
    ):
        """
        Modifies an entry at database
        :param table: collection or table
        :param q_filter: Filter
        :param update_dict: Plain dictionary with the content to be updated. It is a dot separated keys and a value
        :param fail_on_empty: If nothing matches filter it returns None unless this flag is set tu True, in which case
        it raises a DbException
        :param unset: Plain dictionary with the content to be removed if exist. It is a dot separated keys, value is
                      ignored. If not exist, it is ignored
        :param pull: Plain dictionary with the content to be removed from an array. It is a dot separated keys and value
                     if exist in the array is removed. If not exist, it is ignored
        :param pull_list: Same as pull but values are arrays where each item is removed from the array
        :param push: Plain dictionary with the content to be appended to an array. It is a dot separated keys and value
                     is appended to the end of the array
        :param push_list: Same as push but values are arrays where each item is and appended instead of appending the
                          whole array
        :return: Dict with the number of entries modified. None if no matching is found.
        """
        with self.lock:
            for i, db_item in self._find(table, self._format_filter(q_filter)):
                updated = self._update(
                    db_item,
                    update_dict,
                    unset=unset,
                    pull=pull,
                    push=push,
                    push_list=push_list,
                    pull_list=pull_list,
                )
                return {"updated": 1 if updated else 0}
            else:
                if fail_on_empty:
                    raise DbException(
                        "Not found entry with _id='{}'".format(q_filter),
                        HTTPStatus.NOT_FOUND,
                    )
                return None

    def set_list(
        self,
        table,
        q_filter,
        update_dict,
        unset=None,
        pull=None,
        push=None,
        push_list=None,
        pull_list=None,
    ):
        """Modifies al matching entries at database. Same as push. Do not fail if nothing matches"""
        with self.lock:
            updated = 0
            found = 0
            for _, db_item in self._find(table, self._format_filter(q_filter)):
                found += 1
                if self._update(
                    db_item,
                    update_dict,
                    unset=unset,
                    pull=pull,
                    push=push,
                    push_list=push_list,
                    pull_list=pull_list,
                ):
                    updated += 1
            # if not found and fail_on_empty:
            #     raise DbException("Not found entry with '{}'".format(q_filter), HTTPStatus.NOT_FOUND)
            return {"updated": updated} if found else None

    def replace(self, table, _id, indata, fail_on_empty=True):
        """
        Replace the content of an entry
        :param table: collection or table
        :param _id: internal database id
        :param indata: content to replace
        :param fail_on_empty: If nothing matches filter it returns None unless this flag is set tu True, in which case
        it raises a DbException
        :return: Dict with the number of entries replaced
        """
        try:
            with self.lock:
                for i, _ in self._find(table, self._format_filter({"_id": _id})):
                    break
                else:
                    if fail_on_empty:
                        raise DbException(
                            "Not found entry with _id='{}'".format(_id),
                            HTTPStatus.NOT_FOUND,
                        )
                    return None
                self.db[table][i] = deepcopy(indata)
            return {"updated": 1}
        except DbException:
            raise
        except Exception as e:  # TODO refine
            raise DbException(str(e))

    def create(self, table, indata):
        """
        Add a new entry at database
        :param table: collection or table
        :param indata: content to be added
        :return: database '_id' of the inserted element. Raises a DbException on error
        """
        try:
            id = indata.get("_id")
            if not id:
                id = str(uuid4())
                indata["_id"] = id
            with self.lock:
                if table not in self.db:
                    self.db[table] = []
                self.db[table].append(deepcopy(indata))
            return id
        except Exception as e:  # TODO refine
            raise DbException(str(e))

    def create_list(self, table, indata_list):
        """
        Add a new entry at database
        :param table: collection or table
        :param indata_list: list content to be added
        :return: list of inserted 'id's. Raises a DbException on error
        """
        try:
            _ids = []
            with self.lock:
                for indata in indata_list:
                    _id = indata.get("_id")
                    if not _id:
                        _id = str(uuid4())
                        indata["_id"] = _id
                    with self.lock:
                        if table not in self.db:
                            self.db[table] = []
                        self.db[table].append(deepcopy(indata))
                    _ids.append(_id)
            return _ids
        except Exception as e:  # TODO refine
            raise DbException(str(e))


if __name__ == "__main__":
    # some test code
    db = DbMemory()
    db.create("test", {"_id": 1, "data": 1})
    db.create("test", {"_id": 2, "data": 2})
    db.create("test", {"_id": 3, "data": 3})
    print("must be 3 items:", db.get_list("test"))
    print("must return item 2:", db.get_list("test", {"_id": 2}))
    db.del_one("test", {"_id": 2})
    print("must be emtpy:", db.get_list("test", {"_id": 2}))
