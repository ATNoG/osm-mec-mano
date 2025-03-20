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

from base64 import b64decode, b64encode
from copy import deepcopy
from http import HTTPStatus
import logging
import re
from threading import Lock
import typing


from Crypto.Cipher import AES
from motor.motor_asyncio import AsyncIOMotorClient
from osm_common.common_utils import FakeLock
import yaml

__author__ = "Alfonso Tierno <alfonso.tiernosepulveda@telefonica.com>"


DB_NAME = "osm"


class DbException(Exception):
    def __init__(self, message, http_code=HTTPStatus.NOT_FOUND):
        self.http_code = http_code
        Exception.__init__(self, "database exception " + str(message))


class DbBase(object):
    def __init__(self, encoding_type="ascii", logger_name="db", lock=False):
        """
        Constructor of dbBase
        :param logger_name: logging name
        :param lock: Used to protect simultaneous access to the same instance class by several threads:
            False, None: Do not protect, this object will only be accessed by one thread
            True: This object needs to be protected by several threads accessing.
            Lock object. Use thi Lock for the threads access protection
        """
        self.logger = logging.getLogger(logger_name)
        self.secret_key = None  # 32 bytes length array used for encrypt/decrypt
        self.encrypt_mode = AES.MODE_ECB
        self.encoding_type = encoding_type
        if not lock:
            self.lock = FakeLock()
        elif lock is True:
            self.lock = Lock()
        elif isinstance(lock, Lock):
            self.lock = lock
        else:
            raise ValueError("lock parameter must be a Lock classclass or boolean")

    def db_connect(self, config, target_version=None):
        """
        Connect to database
        :param config: Configuration of database. Contains among others:
            host:   database host (mandatory)
            port:   database port (mandatory)
            name:   database name (mandatory)
            user:   database username
            password:   database password
            commonkey: common OSM key used for sensible information encryption
            masterpassword: same as commonkey, for backward compatibility. Deprecated, to be removed in the future
        :param target_version: if provided it checks if database contains required version, raising exception otherwise.
        :return: None or raises DbException on error
        """
        raise DbException("Method 'db_connect' not implemented")

    def db_disconnect(self):
        """
        Disconnect from database
        :return: None
        """
        pass

    def get_list(self, table, q_filter=None):
        """
        Obtain a list of entries matching q_filter
        :param table: collection or table
        :param q_filter: Filter
        :return: a list (can be empty) with the found entries. Raises DbException on error
        """
        raise DbException("Method 'get_list' not implemented")

    def count(self, table, q_filter=None):
        """
        Count the number of entries matching q_filter
        :param table: collection or table
        :param q_filter: Filter
        :return: number of entries found (can be zero)
        :raise: DbException on error
        """
        raise DbException("Method 'count' not implemented")

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
        raise DbException("Method 'get_one' not implemented")

    def del_list(self, table, q_filter=None):
        """
        Deletes all entries that match q_filter
        :param table: collection or table
        :param q_filter: Filter
        :return: Dict with the number of entries deleted
        """
        raise DbException("Method 'del_list' not implemented")

    def del_one(self, table, q_filter=None, fail_on_empty=True):
        """
        Deletes one entry that matches q_filter
        :param table: collection or table
        :param q_filter: Filter
        :param fail_on_empty: If nothing matches filter it returns '0' deleted unless this flag is set tu True, in
        which case it raises a DbException
        :return: Dict with the number of entries deleted
        """
        raise DbException("Method 'del_one' not implemented")

    def create(self, table, indata):
        """
        Add a new entry at database
        :param table: collection or table
        :param indata: content to be added
        :return: database '_id' of the inserted element. Raises a DbException on error
        """
        raise DbException("Method 'create' not implemented")

    def create_list(self, table, indata_list):
        """
        Add several entries at once
        :param table: collection or table
        :param indata_list: list of elements to insert. Each element must be a dictionary.
            An '_id' key based on random uuid is added at each element if missing
        :return: list of inserted '_id's. Exception on error
        """
        raise DbException("Method 'create_list' not implemented")

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
        :param push: Plain dictionary with the content to be appended to an array. It is a dot separated keys and value
                     is appended to the end of the array
        :param pull_list: Same as pull but values are arrays where each item is removed from the array
        :param push_list: Same as push but values are arrays where each item is and appended instead of appending the
                          whole array
        :return: Dict with the number of entries modified. None if no matching is found.
        """
        raise DbException("Method 'set_one' not implemented")

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
        """
        Modifies al matching entries at database
        :param table: collection or table
        :param q_filter: Filter
        :param update_dict: Plain dictionary with the content to be updated. It is a dot separated keys and a value
        :param unset: Plain dictionary with the content to be removed if exist. It is a dot separated keys, value is
                      ignored. If not exist, it is ignored
        :param pull: Plain dictionary with the content to be removed from an array. It is a dot separated keys and value
                     if exist in the array is removed. If not exist, it is ignored
        :param push: Plain dictionary with the content to be appended to an array. It is a dot separated keys and value
                     is appended to the end of the array
        :param pull_list: Same as pull but values are arrays where each item is removed from the array
        :param push_list: Same as push but values are arrays where each item is and appended instead of appending the
                          whole array
        :return: Dict with the number of entries modified
        """
        raise DbException("Method 'set_list' not implemented")

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
        raise DbException("Method 'replace' not implemented")

    def _join_secret_key(self, update_key):
        """
        Returns a xor byte combination of the internal secret_key and the provided update_key.
        It does not modify the internal secret_key. Used for adding salt, join keys, etc.
        :param update_key: Can be a string, byte or None. Recommended a long one (e.g. 32 byte length)
        :return: joined key in bytes with a 32 bytes length. Can be None if both internal secret_key and update_key
                 are None
        """
        if not update_key:
            return self.secret_key
        elif isinstance(update_key, str):
            update_key_bytes = update_key.encode()
        else:
            update_key_bytes = update_key

        new_secret_key = (
            bytearray(self.secret_key) if self.secret_key else bytearray(32)
        )
        for i, b in enumerate(update_key_bytes):
            new_secret_key[i % 32] ^= b
        return bytes(new_secret_key)

    def set_secret_key(self, new_secret_key, replace=False):
        """
        Updates internal secret_key used for encryption, with a byte xor
        :param new_secret_key: string or byte array. It is recommended a 32 byte length
        :param replace: if True, old value of internal secret_key is ignored and replaced. If false, a byte xor is used
        :return: None
        """
        if replace:
            self.secret_key = None
        self.secret_key = self._join_secret_key(new_secret_key)

    def get_secret_key(self):
        """
        Get the database secret key in case it is not done when "connect" is called. It can happens when database is
        empty after an initial install. It should skip if secret is already obtained.
        """
        pass

    @staticmethod
    def pad_data(value: str) -> str:
        if not isinstance(value, str):
            raise DbException(
                f"Incorrect data type: type({value}), string is expected."
            )
        return value + ("\0" * ((16 - len(value)) % 16))

    @staticmethod
    def unpad_data(value: str) -> str:
        if not isinstance(value, str):
            raise DbException(
                f"Incorrect data type: type({value}), string is expected."
            )
        return value.rstrip("\0")

    def _encrypt_value(self, value: str, schema_version: str, salt: str):
        """Encrypt a value.

        Args:
            value   (str):                  value to be encrypted. It is string/unicode
            schema_version  (str):          used for version control. If None or '1.0' no encryption is done.
                                            If '1.1' symmetric AES encryption is done
            salt    (str):                  optional salt to be used. Must be str

        Returns:
            Encrypted content of value  (str)

        """
        if not self.secret_key or not schema_version or schema_version == "1.0":
            return value

        else:
            # Secret key as bytes
            secret_key = self._join_secret_key(salt)
            cipher = AES.new(secret_key, self.encrypt_mode)
            # Padded data as string
            padded_private_msg = self.pad_data(value)
            # Padded data as bytes
            padded_private_msg_bytes = padded_private_msg.encode(self.encoding_type)
            # Encrypt padded data
            encrypted_msg = cipher.encrypt(padded_private_msg_bytes)
            # Base64 encoded encrypted data
            encoded_encrypted_msg = b64encode(encrypted_msg)
            # Converting to string
            return encoded_encrypted_msg.decode(self.encoding_type)

    def encrypt(self, value: str, schema_version: str = None, salt: str = None) -> str:
        """Encrypt a value.

        Args:
            value   (str):                  value to be encrypted. It is string/unicode
            schema_version  (str):          used for version control. If None or '1.0' no encryption is done.
                                            If '1.1' symmetric AES encryption is done
            salt    (str):                  optional salt to be used. Must be str

        Returns:
            Encrypted content of value  (str)

        """
        self.get_secret_key()
        return self._encrypt_value(value, schema_version, salt)

    def _decrypt_value(self, value: str, schema_version: str, salt: str) -> str:
        """Decrypt an encrypted value.
        Args:

            value   (str):                      value to be decrypted. It is a base64 string
            schema_version  (str):              used for known encryption method used.
                                                If None or '1.0' no encryption has been done.
                                                If '1.1' symmetric AES encryption has been done
            salt    (str):                      optional salt to be used

        Returns:
            Plain content of value  (str)

        """
        if not self.secret_key or not schema_version or schema_version == "1.0":
            return value

        else:
            secret_key = self._join_secret_key(salt)
            # Decoding encrypted data, output bytes
            encrypted_msg = b64decode(value)
            cipher = AES.new(secret_key, self.encrypt_mode)
            # Decrypted data, output bytes
            decrypted_msg = cipher.decrypt(encrypted_msg)
            try:
                # Converting to string
                private_msg = decrypted_msg.decode(self.encoding_type)
            except UnicodeDecodeError:
                raise DbException(
                    "Cannot decrypt information. Are you using same COMMONKEY in all OSM components?",
                    http_code=HTTPStatus.INTERNAL_SERVER_ERROR,
                )
            # Unpadded data as string
            return self.unpad_data(private_msg)

    def decrypt(self, value: str, schema_version: str = None, salt: str = None) -> str:
        """Decrypt an encrypted value.
        Args:

            value   (str):                      value to be decrypted. It is a base64 string
            schema_version  (str):              used for known encryption method used.
                                                If None or '1.0' no encryption has been done.
                                                If '1.1' symmetric AES encryption has been done
            salt    (str):                      optional salt to be used

        Returns:
            Plain content of value  (str)

        """
        self.get_secret_key()
        return self._decrypt_value(value, schema_version, salt)

    def encrypt_decrypt_fields(
        self, item, action, fields=None, flags=None, schema_version=None, salt=None
    ):
        if not fields:
            return
        self.get_secret_key()
        actions = ["encrypt", "decrypt"]
        if action.lower() not in actions:
            raise DbException(
                "Unknown action ({}): Must be one of {}".format(action, actions),
                http_code=HTTPStatus.INTERNAL_SERVER_ERROR,
            )
        method = self.encrypt if action.lower() == "encrypt" else self.decrypt
        if flags is None:
            flags = re.I

        def process(_item):
            if isinstance(_item, list):
                for elem in _item:
                    process(elem)
            elif isinstance(_item, dict):
                for key, val in _item.items():
                    if isinstance(val, str):
                        if any(re.search(f, key, flags) for f in fields):
                            _item[key] = method(val, schema_version, salt)
                    else:
                        process(val)

        process(item)


def deep_update_rfc7396(dict_to_change, dict_reference, key_list=None):
    """
    Modifies one dictionary with the information of the other following https://tools.ietf.org/html/rfc7396
    Basically is a recursive python 'dict_to_change.update(dict_reference)', but a value of None is used to delete.
    It implements an extra feature that allows modifying an array. RFC7396 only allows replacing the entire array.
    For that, dict_reference should contains a dict with keys starting by "$" with the following meaning:
        $[index]    <index> is an integer for targeting a concrete index from dict_to_change array. If the value is None
                    the element of the array is deleted, otherwise it is edited.
        $+[index]   The value is inserted at this <index>. A value of None has not sense and an exception is raised.
        $+          The value is appended at the end. A value of None has not sense and an exception is raised.
        $val        It looks for all the items in the array dict_to_change equal to <val>. <val> is evaluated as yaml,
                    that is, numbers are taken as type int, true/false as boolean, etc. Use quotes to force string.
                    Nothing happens if no match is found. If the value is None the matched elements are deleted.
        $key: val   In case a dictionary is passed in yaml format, if looks for all items in the array dict_to_change
                    that are dictionaries and contains this <key> equal to <val>. Several keys can be used by yaml
                    format '{key: val, key: val, ...}'; and all of them must match. Nothing happens if no match is
                    found. If value is None the matched items are deleted, otherwise they are edited.
        $+val       If no match if found (see '$val'), the value is appended to the array. If any match is found nothing
                    is changed. A value of None has not sense.
        $+key: val  If no match if found (see '$key: val'), the value is appended to the array. If any match is found
                    nothing is changed. A value of None has not sense.
    If there are several editions, insertions and deletions; editions and deletions are done first in reverse index
        order; then insertions also in reverse index order; and finally appends in any order. So indexes used at
        insertions must take into account the deleted items.
    :param dict_to_change:  Target dictionary to be changed.
    :param dict_reference: Dictionary that contains changes to be applied.
    :param key_list: This is used internally for recursive calls. Do not fill this parameter.
    :return: none or raises and exception only at array modification when there is a bad format or conflict.
    """

    def _deep_update_array(array_to_change, _dict_reference, _key_list):
        to_append = {}
        to_insert_at_index = {}
        values_to_edit_delete = {}
        indexes_to_edit_delete = []
        array_edition = None
        _key_list.append("")
        for k in _dict_reference:
            _key_list[-1] = str(k)
            if not isinstance(k, str) or not k.startswith("$"):
                if array_edition is True:
                    raise DbException(
                        "Found array edition (keys starting with '$') and pure dictionary edition in the"
                        " same dict at '{}'".format(":".join(_key_list[:-1]))
                    )
                array_edition = False
                continue
            else:
                if array_edition is False:
                    raise DbException(
                        "Found array edition (keys starting with '$') and pure dictionary edition in the"
                        " same dict at '{}'".format(":".join(_key_list[:-1]))
                    )
                array_edition = True
            insert = False
            indexes = []  # indexes to edit or insert
            kitem = k[1:]
            if kitem.startswith("+"):
                insert = True
                kitem = kitem[1:]
                if _dict_reference[k] is None:
                    raise DbException(
                        "A value of None has not sense for insertions at '{}'".format(
                            ":".join(_key_list)
                        )
                    )

            if kitem.startswith("[") and kitem.endswith("]"):
                try:
                    index = int(kitem[1:-1])
                    if index < 0:
                        index += len(array_to_change)
                    if index < 0:
                        index = 0  # skip outside index edition
                    indexes.append(index)
                except Exception:
                    raise DbException(
                        "Wrong format at '{}'. Expecting integer index inside quotes".format(
                            ":".join(_key_list)
                        )
                    )
            elif kitem:
                # match_found_skip = False
                try:
                    filter_in = yaml.safe_load(kitem)
                except Exception:
                    raise DbException(
                        "Wrong format at '{}'. Expecting '$<yaml-format>'".format(
                            ":".join(_key_list)
                        )
                    )
                if isinstance(filter_in, dict):
                    for index, item in enumerate(array_to_change):
                        for filter_k, filter_v in filter_in.items():
                            if (
                                not isinstance(item, dict)
                                or filter_k not in item
                                or item[filter_k] != filter_v
                            ):
                                break
                        else:  # match found
                            if insert:
                                # match_found_skip = True
                                insert = False
                                break
                            else:
                                indexes.append(index)
                else:
                    index = 0
                    try:
                        while True:  # if not match a ValueError exception will be raise
                            index = array_to_change.index(filter_in, index)
                            if insert:
                                # match_found_skip = True
                                insert = False
                                break
                            indexes.append(index)
                            index += 1
                    except ValueError:
                        pass

                # if match_found_skip:
                #     continue
            elif not insert:
                raise DbException(
                    "Wrong format at '{}'. Expecting '$+', '$[<index]' or '$[<filter>]'".format(
                        ":".join(_key_list)
                    )
                )
            for index in indexes:
                if insert:
                    if (
                        index in to_insert_at_index
                        and to_insert_at_index[index] != _dict_reference[k]
                    ):
                        # Several different insertions on the same item of the array
                        raise DbException(
                            "Conflict at '{}'. Several insertions on same array index {}".format(
                                ":".join(_key_list), index
                            )
                        )
                    to_insert_at_index[index] = _dict_reference[k]
                else:
                    if (
                        index in indexes_to_edit_delete
                        and values_to_edit_delete[index] != _dict_reference[k]
                    ):
                        # Several different editions on the same item of the array
                        raise DbException(
                            "Conflict at '{}'. Several editions on array index {}".format(
                                ":".join(_key_list), index
                            )
                        )
                    indexes_to_edit_delete.append(index)
                    values_to_edit_delete[index] = _dict_reference[k]
            if not indexes:
                if insert:
                    to_append[k] = _dict_reference[k]
                # elif _dict_reference[k] is not None:
                #     raise DbException("Not found any match to edit in the array, or wrong format at '{}'".format(
                #         ":".join(_key_list)))

        # edition/deletion is done before insertion
        indexes_to_edit_delete.sort(reverse=True)
        for index in indexes_to_edit_delete:
            _key_list[-1] = str(index)
            try:
                if values_to_edit_delete[index] is None:  # None->Anything
                    try:
                        del array_to_change[index]
                    except IndexError:
                        pass  # it is not consider an error if this index does not exist
                elif not isinstance(
                    values_to_edit_delete[index], dict
                ):  # NotDict->Anything
                    array_to_change[index] = deepcopy(values_to_edit_delete[index])
                elif isinstance(array_to_change[index], dict):  # Dict->Dict
                    deep_update_rfc7396(
                        array_to_change[index], values_to_edit_delete[index], _key_list
                    )
                else:  # Dict->NotDict
                    if isinstance(
                        array_to_change[index], list
                    ):  # Dict->List. Check extra array edition
                        if _deep_update_array(
                            array_to_change[index],
                            values_to_edit_delete[index],
                            _key_list,
                        ):
                            continue
                    array_to_change[index] = deepcopy(values_to_edit_delete[index])
                    # calling deep_update_rfc7396 to delete the None values
                    deep_update_rfc7396(
                        array_to_change[index], values_to_edit_delete[index], _key_list
                    )
            except IndexError:
                raise DbException(
                    "Array edition index out of range at '{}'".format(
                        ":".join(_key_list)
                    )
                )

        # insertion with indexes
        to_insert_indexes = list(to_insert_at_index.keys())
        to_insert_indexes.sort(reverse=True)
        for index in to_insert_indexes:
            array_to_change.insert(index, to_insert_at_index[index])

        # append
        for k, insert_value in to_append.items():
            _key_list[-1] = str(k)
            insert_value_copy = deepcopy(insert_value)
            if isinstance(insert_value_copy, dict):
                # calling deep_update_rfc7396 to delete the None values
                deep_update_rfc7396(insert_value_copy, insert_value, _key_list)
            array_to_change.append(insert_value_copy)

        _key_list.pop()
        if array_edition:
            return True
        return False

    if key_list is None:
        key_list = []
    key_list.append("")
    for k in dict_reference:
        key_list[-1] = str(k)
        if dict_reference[k] is None:  # None->Anything
            if k in dict_to_change:
                del dict_to_change[k]
        elif not isinstance(dict_reference[k], dict):  # NotDict->Anything
            dict_to_change[k] = deepcopy(dict_reference[k])
        elif k not in dict_to_change:  # Dict->Empty
            dict_to_change[k] = deepcopy(dict_reference[k])
            # calling deep_update_rfc7396 to delete the None values
            deep_update_rfc7396(dict_to_change[k], dict_reference[k], key_list)
        elif isinstance(dict_to_change[k], dict):  # Dict->Dict
            deep_update_rfc7396(dict_to_change[k], dict_reference[k], key_list)
        else:  # Dict->NotDict
            if isinstance(
                dict_to_change[k], list
            ):  # Dict->List. Check extra array edition
                if _deep_update_array(dict_to_change[k], dict_reference[k], key_list):
                    continue
            dict_to_change[k] = deepcopy(dict_reference[k])
            # calling deep_update_rfc7396 to delete the None values
            deep_update_rfc7396(dict_to_change[k], dict_reference[k], key_list)
    key_list.pop()


def deep_update(dict_to_change, dict_reference):
    """Maintained for backward compatibility. Use deep_update_rfc7396 instead"""
    return deep_update_rfc7396(dict_to_change, dict_reference)


class Encryption(DbBase):
    def __init__(self, uri, config, encoding_type="ascii", logger_name="db"):
        """Constructor.

        Args:
            uri (str):              Connection string to connect to the database.
            config  (dict):         Additional database info
            encoding_type   (str):  ascii, utf-8 etc.
            logger_name (str):      Logger name

        """
        self._secret_key = None  # 32 bytes length array used for encrypt/decrypt
        self.encrypt_mode = AES.MODE_ECB
        super(Encryption, self).__init__(
            encoding_type=encoding_type, logger_name=logger_name
        )
        self._client = AsyncIOMotorClient(uri)
        self._config = config

    @property
    def secret_key(self):
        return self._secret_key

    @secret_key.setter
    def secret_key(self, value):
        self._secret_key = value

    @property
    def _database(self):
        return self._client[DB_NAME]

    @property
    def _admin_collection(self):
        return self._database["admin"]

    @property
    def database_key(self):
        return self._config.get("database_commonkey")

    async def decrypt_fields(
        self,
        item: dict,
        fields: typing.List[str],
        schema_version: str = None,
        salt: str = None,
    ) -> None:
        """Decrypt fields from a dictionary. Follows the same logic as in osm_common.

        Args:

            item    (dict):         Dictionary with the keys to be decrypted
            fields  (list):          List of keys to decrypt
            schema version  (str):  Schema version. (i.e. 1.11)
            salt    (str):          Salt for the decryption

        """
        flags = re.I

        async def process(_item):
            if isinstance(_item, list):
                for elem in _item:
                    await process(elem)
            elif isinstance(_item, dict):
                for key, val in _item.items():
                    if isinstance(val, str):
                        if any(re.search(f, key, flags) for f in fields):
                            _item[key] = await self.decrypt(val, schema_version, salt)
                    else:
                        await process(val)

        await process(item)

    async def encrypt(
        self, value: str, schema_version: str = None, salt: str = None
    ) -> str:
        """Encrypt a value.

        Args:
            value   (str):                  value to be encrypted. It is string/unicode
            schema_version  (str):          used for version control. If None or '1.0' no encryption is done.
                                            If '1.1' symmetric AES encryption is done
            salt    (str):                  optional salt to be used. Must be str

        Returns:
            Encrypted content of value  (str)

        """
        await self.get_secret_key()
        return self._encrypt_value(value, schema_version, salt)

    async def decrypt(
        self, value: str, schema_version: str = None, salt: str = None
    ) -> str:
        """Decrypt an encrypted value.
        Args:

            value   (str):                      value to be decrypted. It is a base64 string
            schema_version  (str):              used for known encryption method used.
                                                If None or '1.0' no encryption has been done.
                                                If '1.1' symmetric AES encryption has been done
            salt    (str):                      optional salt to be used

        Returns:
            Plain content of value  (str)

        """
        await self.get_secret_key()
        return self._decrypt_value(value, schema_version, salt)

    def _join_secret_key(self, update_key: typing.Any) -> bytes:
        """Join key with secret key.

        Args:

        update_key  (str or bytes):    str or bytes with the to update

        Returns:

            Joined key  (bytes)
        """
        return self._join_keys(update_key, self.secret_key)

    def _join_keys(self, key: typing.Any, secret_key: bytes) -> bytes:
        """Join key with secret_key.

        Args:

            key (str or bytes):         str or bytes of the key to update
            secret_key  (bytes):         bytes of the secret key

        Returns:

            Joined key  (bytes)
        """
        if isinstance(key, str):
            update_key_bytes = key.encode(self.encoding_type)
        else:
            update_key_bytes = key
        new_secret_key = bytearray(secret_key) if secret_key else bytearray(32)
        for i, b in enumerate(update_key_bytes):
            new_secret_key[i % 32] ^= b
        return bytes(new_secret_key)

    async def get_secret_key(self):
        """Get secret key using the database key and the serial key in the DB.
        The key is populated in the property self.secret_key.
        """
        if self.secret_key:
            return
        secret_key = None
        if self.database_key:
            secret_key = self._join_keys(self.database_key, None)
        version_data = await self._admin_collection.find_one({"_id": "version"})
        if version_data and version_data.get("serial"):
            secret_key = self._join_keys(b64decode(version_data["serial"]), secret_key)
        self._secret_key = secret_key
