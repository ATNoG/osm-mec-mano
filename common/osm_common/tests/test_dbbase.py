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
import asyncio
import copy
from copy import deepcopy
import http
from http import HTTPStatus
import logging
from os import urandom
import unittest
from unittest.mock import MagicMock, Mock, patch

from Crypto.Cipher import AES
from osm_common.dbbase import DbBase, DbException, deep_update, Encryption
import pytest


# Variables used in TestBaseEncryption and TestAsyncEncryption
salt = "1afd5d1a-4a7e-4d9c-8c65-251290183106"
value = "private key txt"
padded_value = b"private key txt\0"
padded_encoded_value = b"private key txt\x00"
encoding_type = "ascii"
encyrpt_mode = AES.MODE_ECB
secret_key = b"\xeev\xc2\xb8\xb2#;Ek\xd0\xb5['\x04\xed\x1f\xb9?\xc5Ig\x80\xd5\x8d\x8aT\xd7\xf8Q\xe2u!"
encyrpted_value = "ZW5jcnlwdGVkIGRhdGE="
encyrpted_bytes = b"ZW5jcnlwdGVkIGRhdGE="
data_to_b4_encode = b"encrypted data"
b64_decoded = b"decrypted data"
schema_version = "1.1"
joined_key = b"\x9d\x17\xaf\xc8\xdeF\x1b.\x0e\xa9\xb5['\x04\xed\x1f\xb9?\xc5Ig\x80\xd5\x8d\x8aT\xd7\xf8Q\xe2u!"
serial_bytes = b"\xf8\x96Z\x1c:}\xb5\xdf\x94\x8d\x0f\x807\xe6)\x8f\xf5!\xee}\xc2\xfa\xb3\t\xb9\xe4\r7\x19\x08\xa5b"
base64_decoded_serial = b"g\xbe\xdb"
decrypted_val1 = "BiV9YZEuSRAudqvz7Gs+bg=="
decrypted_val2 = "q4LwnFdoryzbZJM5mCAnpA=="
item = {
    "secret": "mysecret",
    "cacert": "mycacert",
    "path": "/var",
    "ip": "192.168.12.23",
}


def exception_message(message):
    return "database exception " + message


@pytest.fixture
def db_base():
    return DbBase()


def test_constructor():
    db_base = DbBase()
    assert db_base is not None
    assert isinstance(db_base, DbBase)


def test_db_connect(db_base):
    with pytest.raises(DbException) as excinfo:
        db_base.db_connect(None)
    assert str(excinfo.value).startswith(
        exception_message("Method 'db_connect' not implemented")
    )


def test_db_disconnect(db_base):
    db_base.db_disconnect()


def test_get_list(db_base):
    with pytest.raises(DbException) as excinfo:
        db_base.get_list(None, None)
    assert str(excinfo.value).startswith(
        exception_message("Method 'get_list' not implemented")
    )
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


def test_get_one(db_base):
    with pytest.raises(DbException) as excinfo:
        db_base.get_one(None, None, None, None)
    assert str(excinfo.value).startswith(
        exception_message("Method 'get_one' not implemented")
    )
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


def test_create(db_base):
    with pytest.raises(DbException) as excinfo:
        db_base.create(None, None)
    assert str(excinfo.value).startswith(
        exception_message("Method 'create' not implemented")
    )
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


def test_create_list(db_base):
    with pytest.raises(DbException) as excinfo:
        db_base.create_list(None, None)
    assert str(excinfo.value).startswith(
        exception_message("Method 'create_list' not implemented")
    )
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


def test_del_list(db_base):
    with pytest.raises(DbException) as excinfo:
        db_base.del_list(None, None)
    assert str(excinfo.value).startswith(
        exception_message("Method 'del_list' not implemented")
    )
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


def test_del_one(db_base):
    with pytest.raises(DbException) as excinfo:
        db_base.del_one(None, None, None)
    assert str(excinfo.value).startswith(
        exception_message("Method 'del_one' not implemented")
    )
    assert excinfo.value.http_code == http.HTTPStatus.NOT_FOUND


class TestEncryption(unittest.TestCase):
    def setUp(self):
        master_key = "Setting a long master key with numbers 123 and capitals AGHBNHD and symbols %&8)!'"
        db_base1 = DbBase()
        db_base2 = DbBase()
        db_base3 = DbBase()
        # set self.secret_key obtained when connect
        db_base1.set_secret_key(master_key, replace=True)
        db_base1.set_secret_key(urandom(32))
        db_base2.set_secret_key(None, replace=True)
        db_base2.set_secret_key(urandom(30))
        db_base3.set_secret_key(master_key)
        self.db_bases = [db_base1, db_base2, db_base3]

    def test_encrypt_decrypt(self):
        TEST = (
            ("plain text 1 ! ", None),
            ("plain text 2 with salt ! ", "1afd5d1a-4a7e-4d9c-8c65-251290183106"),
        )
        for db_base in self.db_bases:
            for value, salt in TEST:
                # no encryption
                encrypted = db_base.encrypt(value, schema_version="1.0", salt=salt)
                self.assertEqual(
                    encrypted, value, "value '{}' has been encrypted".format(value)
                )
                decrypted = db_base.decrypt(encrypted, schema_version="1.0", salt=salt)
                self.assertEqual(
                    decrypted, value, "value '{}' has been decrypted".format(value)
                )

                # encrypt/decrypt
                encrypted = db_base.encrypt(value, schema_version="1.1", salt=salt)
                self.assertNotEqual(
                    encrypted, value, "value '{}' has not been encrypted".format(value)
                )
                self.assertIsInstance(encrypted, str, "Encrypted is not ascii text")
                decrypted = db_base.decrypt(encrypted, schema_version="1.1", salt=salt)
                self.assertEqual(
                    decrypted, value, "value is not equal after encryption/decryption"
                )

    def test_encrypt_decrypt_salt(self):
        value = "value to be encrypted!"
        encrypted = []
        for db_base in self.db_bases:
            for salt in (None, "salt 1", "1afd5d1a-4a7e-4d9c-8c65-251290183106"):
                # encrypt/decrypt
                encrypted.append(
                    db_base.encrypt(value, schema_version="1.1", salt=salt)
                )
                self.assertNotEqual(
                    encrypted[-1],
                    value,
                    "value '{}' has not been encrypted".format(value),
                )
                self.assertIsInstance(encrypted[-1], str, "Encrypted is not ascii text")
                decrypted = db_base.decrypt(
                    encrypted[-1], schema_version="1.1", salt=salt
                )
                self.assertEqual(
                    decrypted, value, "value is not equal after encryption/decryption"
                )
        for i in range(0, len(encrypted)):
            for j in range(i + 1, len(encrypted)):
                self.assertNotEqual(
                    encrypted[i],
                    encrypted[j],
                    "encryption with different salt must contain different result",
                )
        # decrypt with a different master key
        try:
            decrypted = self.db_bases[-1].decrypt(
                encrypted[0], schema_version="1.1", salt=None
            )
            self.assertNotEqual(
                encrypted[0],
                decrypted,
                "Decryption with different KEY must generate different result",
            )
        except DbException as e:
            self.assertEqual(
                e.http_code,
                HTTPStatus.INTERNAL_SERVER_ERROR,
                "Decryption with different KEY does not provide expected http_code",
            )


class AsyncMock(MagicMock):
    async def __call__(self, *args, **kwargs):
        args = deepcopy(args)
        kwargs = deepcopy(kwargs)
        return super(AsyncMock, self).__call__(*args, **kwargs)


class CopyingMock(MagicMock):
    def __call__(self, *args, **kwargs):
        args = deepcopy(args)
        kwargs = deepcopy(kwargs)
        return super(CopyingMock, self).__call__(*args, **kwargs)


def check_if_assert_not_called(mocks: list):
    for mocking in mocks:
        mocking.assert_not_called()


class TestBaseEncryption(unittest.TestCase):
    @patch("logging.getLogger", autospec=True)
    def setUp(self, mock_logger):
        mock_logger = logging.getLogger()
        mock_logger.disabled = True
        self.db_base = DbBase()
        self.mock_cipher = CopyingMock()
        self.db_base.encoding_type = encoding_type
        self.db_base.encrypt_mode = encyrpt_mode
        self.db_base.secret_key = secret_key
        self.mock_padded_msg = CopyingMock()

    def test_pad_data_len_not_multiplication_of_16(self):
        data = "hello word hello hello word hello word"
        data_len = len(data)
        expected_len = 48
        padded = self.db_base.pad_data(data)
        self.assertEqual(len(padded), expected_len)
        self.assertTrue("\0" * (expected_len - data_len) in padded)

    def test_pad_data_len_multiplication_of_16(self):
        data = "hello word!!!!!!"
        padded = self.db_base.pad_data(data)
        self.assertEqual(padded, data)
        self.assertFalse("\0" in padded)

    def test_pad_data_empty_string(self):
        data = ""
        expected_len = 0
        padded = self.db_base.pad_data(data)
        self.assertEqual(len(padded), expected_len)
        self.assertFalse("\0" in padded)

    def test_pad_data_not_string(self):
        data = None
        with self.assertRaises(Exception) as err:
            self.db_base.pad_data(data)
        self.assertEqual(
            str(err.exception),
            "database exception Incorrect data type: type(None), string is expected.",
        )

    def test_unpad_data_null_char_at_right(self):
        null_padded_data = "hell0word\0\0"
        expected_length = len(null_padded_data) - 2
        unpadded = self.db_base.unpad_data(null_padded_data)
        self.assertEqual(len(unpadded), expected_length)
        self.assertFalse("\0" in unpadded)
        self.assertTrue("0" in unpadded)

    def test_unpad_data_null_char_is_not_rightest(self):
        null_padded_data = "hell0word\r\t\0\n"
        expected_length = len(null_padded_data)
        unpadded = self.db_base.unpad_data(null_padded_data)
        self.assertEqual(len(unpadded), expected_length)
        self.assertTrue("\0" in unpadded)

    def test_unpad_data_with_spaces_at_right(self):
        null_padded_data = "  hell0word\0  "
        expected_length = len(null_padded_data)
        unpadded = self.db_base.unpad_data(null_padded_data)
        self.assertEqual(len(unpadded), expected_length)
        self.assertTrue("\0" in unpadded)

    def test_unpad_data_empty_string(self):
        data = ""
        unpadded = self.db_base.unpad_data(data)
        self.assertEqual(unpadded, "")
        self.assertFalse("\0" in unpadded)

    def test_unpad_data_not_string(self):
        data = None
        with self.assertRaises(Exception) as err:
            self.db_base.unpad_data(data)
        self.assertEqual(
            str(err.exception),
            "database exception Incorrect data type: type(None), string is expected.",
        )

    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "pad_data")
    def test__encrypt_value_schema_version_1_0_none_secret_key_none_salt(
        self, mock_pad_data, mock_join_secret_key
    ):
        """schema_version 1.0, secret_key is None and salt is None."""
        schema_version = "1.0"
        salt = None
        self.db_base.secret_key = None
        result = self.db_base._encrypt_value(value, schema_version, salt)
        self.assertEqual(result, value)
        check_if_assert_not_called([mock_pad_data, mock_join_secret_key])

    @patch("osm_common.dbbase.b64encode")
    @patch("osm_common.dbbase.AES")
    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "pad_data")
    def test__encrypt_value_schema_version_1_1_with_secret_key_exists_with_salt(
        self,
        mock_pad_data,
        mock_join_secret_key,
        mock_aes,
        mock_b64_encode,
    ):
        """schema_version 1.1, secret_key exists, salt exists."""
        mock_aes.new.return_value = self.mock_cipher
        self.mock_cipher.encrypt.return_value = data_to_b4_encode
        self.mock_padded_msg.return_value = padded_value
        mock_pad_data.return_value = self.mock_padded_msg
        self.mock_padded_msg.encode.return_value = padded_encoded_value

        mock_b64_encode.return_value = encyrpted_bytes

        result = self.db_base._encrypt_value(value, schema_version, salt)

        self.assertTrue(isinstance(result, str))
        self.assertEqual(result, encyrpted_value)
        mock_join_secret_key.assert_called_once_with(salt)
        _call_mock_aes_new = mock_aes.new.call_args_list[0].args
        self.assertEqual(_call_mock_aes_new[1], AES.MODE_ECB)
        mock_pad_data.assert_called_once_with(value)
        mock_b64_encode.assert_called_once_with(data_to_b4_encode)
        self.mock_cipher.encrypt.assert_called_once_with(padded_encoded_value)
        self.mock_padded_msg.encode.assert_called_with(encoding_type)

    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "pad_data")
    def test__encrypt_value_schema_version_1_0_secret_key_not_exists(
        self, mock_pad_data, mock_join_secret_key
    ):
        """schema_version 1.0, secret_key is None, salt exists."""
        schema_version = "1.0"
        self.db_base.secret_key = None
        result = self.db_base._encrypt_value(value, schema_version, salt)
        self.assertEqual(result, value)
        check_if_assert_not_called([mock_pad_data, mock_join_secret_key])

    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "pad_data")
    def test__encrypt_value_schema_version_1_1_secret_key_not_exists(
        self, mock_pad_data, mock_join_secret_key
    ):
        """schema_version 1.1, secret_key is None, salt exists."""
        self.db_base.secret_key = None
        result = self.db_base._encrypt_value(value, schema_version, salt)
        self.assertEqual(result, value)
        check_if_assert_not_called([mock_pad_data, mock_join_secret_key])

    @patch("osm_common.dbbase.b64encode")
    @patch("osm_common.dbbase.AES")
    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "pad_data")
    def test__encrypt_value_schema_version_1_1_secret_key_exists_without_salt(
        self,
        mock_pad_data,
        mock_join_secret_key,
        mock_aes,
        mock_b64_encode,
    ):
        """schema_version 1.1, secret_key exists, salt is None."""
        salt = None
        mock_aes.new.return_value = self.mock_cipher
        self.mock_cipher.encrypt.return_value = data_to_b4_encode

        self.mock_padded_msg.return_value = padded_value
        mock_pad_data.return_value = self.mock_padded_msg
        self.mock_padded_msg.encode.return_value = padded_encoded_value

        mock_b64_encode.return_value = encyrpted_bytes

        result = self.db_base._encrypt_value(value, schema_version, salt)

        self.assertEqual(result, encyrpted_value)
        mock_join_secret_key.assert_called_once_with(salt)
        _call_mock_aes_new = mock_aes.new.call_args_list[0].args
        self.assertEqual(_call_mock_aes_new[1], AES.MODE_ECB)
        mock_pad_data.assert_called_once_with(value)
        mock_b64_encode.assert_called_once_with(data_to_b4_encode)
        self.mock_cipher.encrypt.assert_called_once_with(padded_encoded_value)
        self.mock_padded_msg.encode.assert_called_with(encoding_type)

    @patch("osm_common.dbbase.b64encode")
    @patch("osm_common.dbbase.AES")
    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "pad_data")
    def test__encrypt_value_invalid_encrpt_mode(
        self,
        mock_pad_data,
        mock_join_secret_key,
        mock_aes,
        mock_b64_encode,
    ):
        """encrypt_mode is invalid."""
        mock_aes.new.side_effect = Exception("Invalid ciphering mode.")
        self.db_base.encrypt_mode = "AES.MODE_XXX"

        with self.assertRaises(Exception) as err:
            self.db_base._encrypt_value(value, schema_version, salt)

        self.assertEqual(str(err.exception), "Invalid ciphering mode.")
        mock_join_secret_key.assert_called_once_with(salt)
        _call_mock_aes_new = mock_aes.new.call_args_list[0].args
        self.assertEqual(_call_mock_aes_new[1], "AES.MODE_XXX")
        check_if_assert_not_called([mock_pad_data, mock_b64_encode])

    @patch("osm_common.dbbase.b64encode")
    @patch("osm_common.dbbase.AES")
    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "pad_data")
    def test__encrypt_value_schema_version_1_1_secret_key_exists_value_none(
        self,
        mock_pad_data,
        mock_join_secret_key,
        mock_aes,
        mock_b64_encode,
    ):
        """schema_version 1.1, secret_key exists, value is None."""
        value = None
        mock_aes.new.return_value = self.mock_cipher
        mock_pad_data.side_effect = DbException(
            "Incorrect data type: type(None), string is expected."
        )

        with self.assertRaises(Exception) as err:
            self.db_base._encrypt_value(value, schema_version, salt)
        self.assertEqual(
            str(err.exception),
            "database exception Incorrect data type: type(None), string is expected.",
        )

        mock_join_secret_key.assert_called_once_with(salt)
        _call_mock_aes_new = mock_aes.new.call_args_list[0].args
        self.assertEqual(_call_mock_aes_new[1], AES.MODE_ECB)
        mock_pad_data.assert_called_once_with(value)
        check_if_assert_not_called(
            [mock_b64_encode, self.mock_cipher.encrypt, mock_b64_encode]
        )

    @patch("osm_common.dbbase.b64encode")
    @patch("osm_common.dbbase.AES")
    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "pad_data")
    def test__encrypt_value_join_secret_key_raises(
        self,
        mock_pad_data,
        mock_join_secret_key,
        mock_aes,
        mock_b64_encode,
    ):
        """Method join_secret_key raises DbException."""
        salt = b"3434o34-3wewrwr-222424-2242dwew"

        mock_join_secret_key.side_effect = DbException("Unexpected type")

        mock_aes.new.return_value = self.mock_cipher

        with self.assertRaises(Exception) as err:
            self.db_base._encrypt_value(value, schema_version, salt)

        self.assertEqual(str(err.exception), "database exception Unexpected type")
        check_if_assert_not_called(
            [mock_pad_data, mock_aes.new, mock_b64_encode, self.mock_cipher.encrypt]
        )
        mock_join_secret_key.assert_called_once_with(salt)

    @patch("osm_common.dbbase.b64encode")
    @patch("osm_common.dbbase.AES")
    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "pad_data")
    def test__encrypt_value_schema_version_1_1_secret_key_exists_b64_encode_raises(
        self,
        mock_pad_data,
        mock_join_secret_key,
        mock_aes,
        mock_b64_encode,
    ):
        """schema_version 1.1, secret_key exists, b64encode raises TypeError."""
        mock_aes.new.return_value = self.mock_cipher
        self.mock_cipher.encrypt.return_value = "encrypted data"

        self.mock_padded_msg.return_value = padded_value
        mock_pad_data.return_value = self.mock_padded_msg
        self.mock_padded_msg.encode.return_value = padded_encoded_value

        mock_b64_encode.side_effect = TypeError(
            "A bytes-like object is required, not 'str'"
        )

        with self.assertRaises(Exception) as error:
            self.db_base._encrypt_value(value, schema_version, salt)
        self.assertEqual(
            str(error.exception), "A bytes-like object is required, not 'str'"
        )
        mock_join_secret_key.assert_called_once_with(salt)
        _call_mock_aes_new = mock_aes.new.call_args_list[0].args
        self.assertEqual(_call_mock_aes_new[1], AES.MODE_ECB)
        mock_pad_data.assert_called_once_with(value)
        self.mock_cipher.encrypt.assert_called_once_with(padded_encoded_value)
        self.mock_padded_msg.encode.assert_called_with(encoding_type)
        mock_b64_encode.assert_called_once_with("encrypted data")

    @patch("osm_common.dbbase.b64encode")
    @patch("osm_common.dbbase.AES")
    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "pad_data")
    def test__encrypt_value_cipher_encrypt_raises(
        self,
        mock_pad_data,
        mock_join_secret_key,
        mock_aes,
        mock_b64_encode,
    ):
        """AES encrypt method raises Exception."""
        mock_aes.new.return_value = self.mock_cipher
        self.mock_cipher.encrypt.side_effect = Exception("Invalid data type.")

        self.mock_padded_msg.return_value = padded_value
        mock_pad_data.return_value = self.mock_padded_msg
        self.mock_padded_msg.encode.return_value = padded_encoded_value

        with self.assertRaises(Exception) as error:
            self.db_base._encrypt_value(value, schema_version, salt)

        self.assertEqual(str(error.exception), "Invalid data type.")
        mock_join_secret_key.assert_called_once_with(salt)
        _call_mock_aes_new = mock_aes.new.call_args_list[0].args
        self.assertEqual(_call_mock_aes_new[1], AES.MODE_ECB)
        mock_pad_data.assert_called_once_with(value)
        self.mock_cipher.encrypt.assert_called_once_with(padded_encoded_value)
        self.mock_padded_msg.encode.assert_called_with(encoding_type)
        mock_b64_encode.assert_not_called()

    @patch.object(DbBase, "get_secret_key")
    @patch.object(DbBase, "_encrypt_value")
    def test_encrypt_without_schema_version_without_salt(
        self, mock_encrypt_value, mock_get_secret_key
    ):
        """schema and salt is None."""
        mock_encrypt_value.return_value = encyrpted_value
        result = self.db_base.encrypt(value)
        mock_encrypt_value.assert_called_once_with(value, None, None)
        mock_get_secret_key.assert_called_once()
        self.assertEqual(result, encyrpted_value)

    @patch.object(DbBase, "get_secret_key")
    @patch.object(DbBase, "_encrypt_value")
    def test_encrypt_with_schema_version_with_salt(
        self, mock_encrypt_value, mock_get_secret_key
    ):
        """schema version exists, salt is None."""
        mock_encrypt_value.return_value = encyrpted_value
        result = self.db_base.encrypt(value, schema_version, salt)
        mock_encrypt_value.assert_called_once_with(value, schema_version, salt)
        mock_get_secret_key.assert_called_once()
        self.assertEqual(result, encyrpted_value)

    @patch.object(DbBase, "get_secret_key")
    @patch.object(DbBase, "_encrypt_value")
    def test_encrypt_get_secret_key_raises(
        self, mock_encrypt_value, mock_get_secret_key
    ):
        """get_secret_key method raises DbException."""
        mock_get_secret_key.side_effect = DbException("KeyError")
        with self.assertRaises(Exception) as error:
            self.db_base.encrypt(value)
        self.assertEqual(str(error.exception), "database exception KeyError")
        mock_encrypt_value.assert_not_called()
        mock_get_secret_key.assert_called_once()

    @patch.object(DbBase, "get_secret_key")
    @patch.object(DbBase, "_encrypt_value")
    def test_encrypt_encrypt_raises(self, mock_encrypt_value, mock_get_secret_key):
        """_encrypt method raises DbException."""
        mock_encrypt_value.side_effect = DbException(
            "Incorrect data type: type(None), string is expected."
        )
        with self.assertRaises(Exception) as error:
            self.db_base.encrypt(value, schema_version, salt)
        self.assertEqual(
            str(error.exception),
            "database exception Incorrect data type: type(None), string is expected.",
        )
        mock_encrypt_value.assert_called_once_with(value, schema_version, salt)
        mock_get_secret_key.assert_called_once()

    @patch("osm_common.dbbase.b64decode")
    @patch("osm_common.dbbase.AES")
    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "unpad_data")
    def test__decrypt_value_schema_version_1_1_secret_key_exists_without_salt(
        self,
        mock_unpad_data,
        mock_join_secret_key,
        mock_aes,
        mock_b64_decode,
    ):
        """schema_version 1.1, secret_key exists, salt is None."""
        salt = None
        mock_aes.new.return_value = self.mock_cipher
        self.mock_cipher.decrypt.return_value = padded_encoded_value

        mock_b64_decode.return_value = b64_decoded

        mock_unpad_data.return_value = value

        result = self.db_base._decrypt_value(encyrpted_value, schema_version, salt)
        self.assertEqual(result, value)

        mock_join_secret_key.assert_called_once_with(salt)
        _call_mock_aes_new = mock_aes.new.call_args_list[0].args
        self.assertEqual(_call_mock_aes_new[1], AES.MODE_ECB)
        mock_unpad_data.assert_called_once_with("private key txt\0")
        mock_b64_decode.assert_called_once_with(encyrpted_value)
        self.mock_cipher.decrypt.assert_called_once_with(b64_decoded)

    @patch("osm_common.dbbase.b64decode")
    @patch("osm_common.dbbase.AES")
    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "unpad_data")
    def test__decrypt_value_schema_version_1_1_secret_key_exists_with_salt(
        self,
        mock_unpad_data,
        mock_join_secret_key,
        mock_aes,
        mock_b64_decode,
    ):
        """schema_version 1.1, secret_key exists, salt is None."""
        mock_aes.new.return_value = self.mock_cipher
        self.mock_cipher.decrypt.return_value = padded_encoded_value

        mock_b64_decode.return_value = b64_decoded

        mock_unpad_data.return_value = value

        result = self.db_base._decrypt_value(encyrpted_value, schema_version, salt)
        self.assertEqual(result, value)

        mock_join_secret_key.assert_called_once_with(salt)
        _call_mock_aes_new = mock_aes.new.call_args_list[0].args
        self.assertEqual(_call_mock_aes_new[1], AES.MODE_ECB)
        mock_unpad_data.assert_called_once_with("private key txt\0")
        mock_b64_decode.assert_called_once_with(encyrpted_value)
        self.mock_cipher.decrypt.assert_called_once_with(b64_decoded)

    @patch("osm_common.dbbase.b64decode")
    @patch("osm_common.dbbase.AES")
    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "unpad_data")
    def test__decrypt_value_schema_version_1_1_without_secret_key(
        self,
        mock_unpad_data,
        mock_join_secret_key,
        mock_aes,
        mock_b64_decode,
    ):
        """schema_version 1.1, secret_key is None, salt exists."""
        self.db_base.secret_key = None

        result = self.db_base._decrypt_value(encyrpted_value, schema_version, salt)

        self.assertEqual(result, encyrpted_value)
        check_if_assert_not_called(
            [
                mock_join_secret_key,
                mock_aes.new,
                mock_unpad_data,
                mock_b64_decode,
                self.mock_cipher.decrypt,
            ]
        )

    @patch("osm_common.dbbase.b64decode")
    @patch("osm_common.dbbase.AES")
    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "unpad_data")
    def test__decrypt_value_schema_version_1_0_with_secret_key(
        self,
        mock_unpad_data,
        mock_join_secret_key,
        mock_aes,
        mock_b64_decode,
    ):
        """schema_version 1.0, secret_key exists, salt exists."""
        schema_version = "1.0"
        result = self.db_base._decrypt_value(encyrpted_value, schema_version, salt)

        self.assertEqual(result, encyrpted_value)
        check_if_assert_not_called(
            [
                mock_join_secret_key,
                mock_aes.new,
                mock_unpad_data,
                mock_b64_decode,
                self.mock_cipher.decrypt,
            ]
        )

    @patch("osm_common.dbbase.b64decode")
    @patch("osm_common.dbbase.AES")
    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "unpad_data")
    def test__decrypt_value_join_secret_key_raises(
        self,
        mock_unpad_data,
        mock_join_secret_key,
        mock_aes,
        mock_b64_decode,
    ):
        """_join_secret_key raises TypeError."""
        salt = object()
        mock_join_secret_key.side_effect = TypeError("'type' object is not iterable")

        with self.assertRaises(Exception) as error:
            self.db_base._decrypt_value(encyrpted_value, schema_version, salt)
        self.assertEqual(str(error.exception), "'type' object is not iterable")

        mock_join_secret_key.assert_called_once_with(salt)
        check_if_assert_not_called(
            [mock_aes.new, mock_unpad_data, mock_b64_decode, self.mock_cipher.decrypt]
        )

    @patch("osm_common.dbbase.b64decode")
    @patch("osm_common.dbbase.AES")
    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "unpad_data")
    def test__decrypt_value_b64decode_raises(
        self,
        mock_unpad_data,
        mock_join_secret_key,
        mock_aes,
        mock_b64_decode,
    ):
        """b64decode raises TypeError."""
        mock_b64_decode.side_effect = TypeError(
            "A str-like object is required, not 'bytes'"
        )
        with self.assertRaises(Exception) as error:
            self.db_base._decrypt_value(encyrpted_value, schema_version, salt)
        self.assertEqual(
            str(error.exception), "A str-like object is required, not 'bytes'"
        )

        mock_b64_decode.assert_called_once_with(encyrpted_value)
        mock_join_secret_key.assert_called_once_with(salt)
        check_if_assert_not_called(
            [mock_aes.new, self.mock_cipher.decrypt, mock_unpad_data]
        )

    @patch("osm_common.dbbase.b64decode")
    @patch("osm_common.dbbase.AES")
    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "unpad_data")
    def test__decrypt_value_invalid_encrypt_mode(
        self,
        mock_unpad_data,
        mock_join_secret_key,
        mock_aes,
        mock_b64_decode,
    ):
        """Invalid AES encrypt mode."""
        mock_aes.new.side_effect = Exception("Invalid ciphering mode.")
        self.db_base.encrypt_mode = "AES.MODE_XXX"

        mock_b64_decode.return_value = b64_decoded
        with self.assertRaises(Exception) as error:
            self.db_base._decrypt_value(encyrpted_value, schema_version, salt)

        self.assertEqual(str(error.exception), "Invalid ciphering mode.")
        mock_join_secret_key.assert_called_once_with(salt)
        _call_mock_aes_new = mock_aes.new.call_args_list[0].args
        self.assertEqual(_call_mock_aes_new[1], "AES.MODE_XXX")
        mock_b64_decode.assert_called_once_with(encyrpted_value)
        check_if_assert_not_called([mock_unpad_data, self.mock_cipher.decrypt])

    @patch("osm_common.dbbase.b64decode")
    @patch("osm_common.dbbase.AES")
    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "unpad_data")
    def test__decrypt_value_cipher_decrypt_raises(
        self,
        mock_unpad_data,
        mock_join_secret_key,
        mock_aes,
        mock_b64_decode,
    ):
        """AES decrypt raises Exception."""
        mock_b64_decode.return_value = b64_decoded

        mock_aes.new.return_value = self.mock_cipher
        self.mock_cipher.decrypt.side_effect = Exception("Invalid data type.")

        with self.assertRaises(Exception) as error:
            self.db_base._decrypt_value(encyrpted_value, schema_version, salt)
        self.assertEqual(str(error.exception), "Invalid data type.")

        mock_join_secret_key.assert_called_once_with(salt)
        _call_mock_aes_new = mock_aes.new.call_args_list[0].args
        self.assertEqual(_call_mock_aes_new[1], AES.MODE_ECB)
        mock_b64_decode.assert_called_once_with(encyrpted_value)
        self.mock_cipher.decrypt.assert_called_once_with(b64_decoded)
        mock_unpad_data.assert_not_called()

    @patch("osm_common.dbbase.b64decode")
    @patch("osm_common.dbbase.AES")
    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "unpad_data")
    def test__decrypt_value_decode_raises(
        self,
        mock_unpad_data,
        mock_join_secret_key,
        mock_aes,
        mock_b64_decode,
    ):
        """Decode raises UnicodeDecodeError."""
        mock_aes.new.return_value = self.mock_cipher
        self.mock_cipher.decrypt.return_value = b"\xd0\x000091"

        mock_b64_decode.return_value = b64_decoded

        mock_unpad_data.return_value = value
        with self.assertRaises(Exception) as error:
            self.db_base._decrypt_value(encyrpted_value, schema_version, salt)
        self.assertEqual(
            str(error.exception),
            "database exception Cannot decrypt information. Are you using same COMMONKEY in all OSM components?",
        )
        self.assertEqual(type(error.exception), DbException)
        mock_join_secret_key.assert_called_once_with(salt)
        _call_mock_aes_new = mock_aes.new.call_args_list[0].args
        self.assertEqual(_call_mock_aes_new[1], AES.MODE_ECB)
        mock_b64_decode.assert_called_once_with(encyrpted_value)
        self.mock_cipher.decrypt.assert_called_once_with(b64_decoded)
        mock_unpad_data.assert_not_called()

    @patch("osm_common.dbbase.b64decode")
    @patch("osm_common.dbbase.AES")
    @patch.object(DbBase, "_join_secret_key")
    @patch.object(DbBase, "unpad_data")
    def test__decrypt_value_unpad_data_raises(
        self,
        mock_unpad_data,
        mock_join_secret_key,
        mock_aes,
        mock_b64_decode,
    ):
        """Method unpad_data raises error."""
        mock_decrypted_message = MagicMock()
        mock_decrypted_message.decode.return_value = None
        mock_aes.new.return_value = self.mock_cipher
        self.mock_cipher.decrypt.return_value = mock_decrypted_message
        mock_unpad_data.side_effect = DbException(
            "Incorrect data type: type(None), string is expected."
        )
        mock_b64_decode.return_value = b64_decoded

        with self.assertRaises(Exception) as error:
            self.db_base._decrypt_value(encyrpted_value, schema_version, salt)
        self.assertEqual(
            str(error.exception),
            "database exception Incorrect data type: type(None), string is expected.",
        )
        self.assertEqual(type(error.exception), DbException)
        mock_join_secret_key.assert_called_once_with(salt)
        _call_mock_aes_new = mock_aes.new.call_args_list[0].args
        self.assertEqual(_call_mock_aes_new[1], AES.MODE_ECB)
        mock_b64_decode.assert_called_once_with(encyrpted_value)
        self.mock_cipher.decrypt.assert_called_once_with(b64_decoded)
        mock_decrypted_message.decode.assert_called_once_with(
            self.db_base.encoding_type
        )
        mock_unpad_data.assert_called_once_with(None)

    @patch.object(DbBase, "get_secret_key")
    @patch.object(DbBase, "_decrypt_value")
    def test_decrypt_without_schema_version_without_salt(
        self, mock_decrypt_value, mock_get_secret_key
    ):
        """schema_version is None, salt is None."""
        mock_decrypt_value.return_value = encyrpted_value
        result = self.db_base.decrypt(value)
        mock_decrypt_value.assert_called_once_with(value, None, None)
        mock_get_secret_key.assert_called_once()
        self.assertEqual(result, encyrpted_value)

    @patch.object(DbBase, "get_secret_key")
    @patch.object(DbBase, "_decrypt_value")
    def test_decrypt_with_schema_version_with_salt(
        self, mock_decrypt_value, mock_get_secret_key
    ):
        """schema_version and salt exist."""
        mock_decrypt_value.return_value = encyrpted_value
        result = self.db_base.decrypt(value, schema_version, salt)
        mock_decrypt_value.assert_called_once_with(value, schema_version, salt)
        mock_get_secret_key.assert_called_once()
        self.assertEqual(result, encyrpted_value)

    @patch.object(DbBase, "get_secret_key")
    @patch.object(DbBase, "_decrypt_value")
    def test_decrypt_get_secret_key_raises(
        self, mock_decrypt_value, mock_get_secret_key
    ):
        """Method get_secret_key raises KeyError."""
        mock_get_secret_key.side_effect = DbException("KeyError")
        with self.assertRaises(Exception) as error:
            self.db_base.decrypt(value)
        self.assertEqual(str(error.exception), "database exception KeyError")
        mock_decrypt_value.assert_not_called()
        mock_get_secret_key.assert_called_once()

    @patch.object(DbBase, "get_secret_key")
    @patch.object(DbBase, "_decrypt_value")
    def test_decrypt_decrypt_value_raises(
        self, mock_decrypt_value, mock_get_secret_key
    ):
        """Method _decrypt raises error."""
        mock_decrypt_value.side_effect = DbException(
            "Incorrect data type: type(None), string is expected."
        )
        with self.assertRaises(Exception) as error:
            self.db_base.decrypt(value, schema_version, salt)
        self.assertEqual(
            str(error.exception),
            "database exception Incorrect data type: type(None), string is expected.",
        )
        mock_decrypt_value.assert_called_once_with(value, schema_version, salt)
        mock_get_secret_key.assert_called_once()

    def test_encrypt_decrypt_with_schema_version_1_1_with_salt(self):
        """Encrypt and decrypt with schema version 1.1, salt exists."""
        encrypted_msg = self.db_base.encrypt(value, schema_version, salt)
        decrypted_msg = self.db_base.decrypt(encrypted_msg, schema_version, salt)
        self.assertEqual(value, decrypted_msg)

    def test_encrypt_decrypt_with_schema_version_1_0_with_salt(self):
        """Encrypt and decrypt with schema version 1.0, salt exists."""
        schema_version = "1.0"
        encrypted_msg = self.db_base.encrypt(value, schema_version, salt)
        decrypted_msg = self.db_base.decrypt(encrypted_msg, schema_version, salt)
        self.assertEqual(value, decrypted_msg)

    def test_encrypt_decrypt_with_schema_version_1_1_without_salt(self):
        """Encrypt and decrypt with schema version 1.1 and without salt."""
        salt = None
        encrypted_msg = self.db_base.encrypt(value, schema_version, salt)
        decrypted_msg = self.db_base.decrypt(encrypted_msg, schema_version, salt)
        self.assertEqual(value, decrypted_msg)


class TestAsyncEncryption(unittest.TestCase):
    @patch("logging.getLogger", autospec=True)
    def setUp(self, mock_logger):
        mock_logger = logging.getLogger()
        mock_logger.disabled = True
        self.encryption = Encryption(uri="uri", config={})
        self.encryption.encoding_type = encoding_type
        self.encryption.encrypt_mode = encyrpt_mode
        self.encryption._secret_key = secret_key
        self.admin_collection = Mock()
        self.admin_collection.find_one = AsyncMock()
        self.encryption._client = {
            "osm": {
                "admin": self.admin_collection,
            }
        }

    @patch.object(Encryption, "decrypt", new_callable=AsyncMock)
    def test_decrypt_fields_with_item_with_fields(self, mock_decrypt):
        """item and fields exist."""
        mock_decrypt.side_effect = [decrypted_val1, decrypted_val2]
        input_item = copy.deepcopy(item)
        expected_item = {
            "secret": decrypted_val1,
            "cacert": decrypted_val2,
            "path": "/var",
            "ip": "192.168.12.23",
        }
        fields = ["secret", "cacert"]

        asyncio.run(
            self.encryption.decrypt_fields(input_item, fields, schema_version, salt)
        )
        self.assertEqual(input_item, expected_item)
        _call_mock_decrypt = mock_decrypt.call_args_list
        self.assertEqual(_call_mock_decrypt[0].args, ("mysecret", "1.1", salt))
        self.assertEqual(_call_mock_decrypt[1].args, ("mycacert", "1.1", salt))

    @patch.object(Encryption, "decrypt", new_callable=AsyncMock)
    def test_decrypt_fields_empty_item_with_fields(self, mock_decrypt):
        """item is empty and fields exists."""
        input_item = {}
        fields = ["secret", "cacert"]
        asyncio.run(
            self.encryption.decrypt_fields(input_item, fields, schema_version, salt)
        )
        self.assertEqual(input_item, {})
        mock_decrypt.assert_not_called()

    @patch.object(Encryption, "decrypt", new_callable=AsyncMock)
    def test_decrypt_fields_with_item_without_fields(self, mock_decrypt):
        """item exists and fields is empty."""
        input_item = copy.deepcopy(item)
        fields = []
        asyncio.run(
            self.encryption.decrypt_fields(input_item, fields, schema_version, salt)
        )
        self.assertEqual(input_item, item)
        mock_decrypt.assert_not_called()

    @patch.object(Encryption, "decrypt", new_callable=AsyncMock)
    def test_decrypt_fields_with_item_with_single_field(self, mock_decrypt):
        """item exists and field has single value."""
        mock_decrypt.return_value = decrypted_val1
        fields = ["secret"]
        input_item = copy.deepcopy(item)
        expected_item = {
            "secret": decrypted_val1,
            "cacert": "mycacert",
            "path": "/var",
            "ip": "192.168.12.23",
        }
        asyncio.run(
            self.encryption.decrypt_fields(input_item, fields, schema_version, salt)
        )
        self.assertEqual(input_item, expected_item)
        _call_mock_decrypt = mock_decrypt.call_args_list
        self.assertEqual(_call_mock_decrypt[0].args, ("mysecret", "1.1", salt))

    @patch.object(Encryption, "decrypt", new_callable=AsyncMock)
    def test_decrypt_fields_with_item_with_field_none_salt_1_0_schema_version(
        self, mock_decrypt
    ):
        """item exists and field has single value, salt is None, schema version is 1.0."""
        schema_version = "1.0"
        salt = None
        mock_decrypt.return_value = "mysecret"
        input_item = copy.deepcopy(item)
        fields = ["secret"]
        asyncio.run(
            self.encryption.decrypt_fields(input_item, fields, schema_version, salt)
        )
        self.assertEqual(input_item, item)
        _call_mock_decrypt = mock_decrypt.call_args_list
        self.assertEqual(_call_mock_decrypt[0].args, ("mysecret", "1.0", None))

    @patch.object(Encryption, "decrypt", new_callable=AsyncMock)
    def test_decrypt_fields_decrypt_raises(self, mock_decrypt):
        """Method decrypt raises error."""
        mock_decrypt.side_effect = DbException(
            "Incorrect data type: type(None), string is expected."
        )
        fields = ["secret"]
        input_item = copy.deepcopy(item)
        with self.assertRaises(Exception) as error:
            asyncio.run(
                self.encryption.decrypt_fields(input_item, fields, schema_version, salt)
            )
        self.assertEqual(
            str(error.exception),
            "database exception Incorrect data type: type(None), string is expected.",
        )
        self.assertEqual(input_item, item)
        _call_mock_decrypt = mock_decrypt.call_args_list
        self.assertEqual(_call_mock_decrypt[0].args, ("mysecret", "1.1", salt))

    @patch.object(Encryption, "get_secret_key", new_callable=AsyncMock)
    @patch.object(Encryption, "_encrypt_value")
    def test_encrypt(self, mock_encrypt_value, mock_get_secret_key):
        """Method decrypt raises error."""
        mock_encrypt_value.return_value = encyrpted_value
        result = asyncio.run(self.encryption.encrypt(value, schema_version, salt))
        self.assertEqual(result, encyrpted_value)
        mock_get_secret_key.assert_called_once()
        mock_encrypt_value.assert_called_once_with(value, schema_version, salt)

    @patch.object(Encryption, "get_secret_key", new_callable=AsyncMock)
    @patch.object(Encryption, "_encrypt_value")
    def test_encrypt_get_secret_key_raises(
        self, mock_encrypt_value, mock_get_secret_key
    ):
        """Method get_secret_key raises error."""
        mock_get_secret_key.side_effect = DbException("Unexpected type.")
        with self.assertRaises(Exception) as error:
            asyncio.run(self.encryption.encrypt(value, schema_version, salt))
        self.assertEqual(str(error.exception), "database exception Unexpected type.")
        mock_get_secret_key.assert_called_once()
        mock_encrypt_value.assert_not_called()

    @patch.object(Encryption, "get_secret_key", new_callable=AsyncMock)
    @patch.object(Encryption, "_encrypt_value")
    def test_encrypt_get_encrypt_raises(self, mock_encrypt_value, mock_get_secret_key):
        """Method _encrypt raises error."""
        mock_encrypt_value.side_effect = TypeError(
            "A bytes-like object is required, not 'str'"
        )
        with self.assertRaises(Exception) as error:
            asyncio.run(self.encryption.encrypt(value, schema_version, salt))
        self.assertEqual(
            str(error.exception), "A bytes-like object is required, not 'str'"
        )
        mock_get_secret_key.assert_called_once()
        mock_encrypt_value.assert_called_once_with(value, schema_version, salt)

    @patch.object(Encryption, "get_secret_key", new_callable=AsyncMock)
    @patch.object(Encryption, "_decrypt_value")
    def test_decrypt(self, mock_decrypt_value, mock_get_secret_key):
        """Decrypted successfully."""
        mock_decrypt_value.return_value = value
        result = asyncio.run(
            self.encryption.decrypt(encyrpted_value, schema_version, salt)
        )
        self.assertEqual(result, value)
        mock_get_secret_key.assert_called_once()
        mock_decrypt_value.assert_called_once_with(
            encyrpted_value, schema_version, salt
        )

    @patch.object(Encryption, "get_secret_key", new_callable=AsyncMock)
    @patch.object(Encryption, "_decrypt_value")
    def test_decrypt_get_secret_key_raises(
        self, mock_decrypt_value, mock_get_secret_key
    ):
        """Method get_secret_key raises error."""
        mock_get_secret_key.side_effect = DbException("Unexpected type.")
        with self.assertRaises(Exception) as error:
            asyncio.run(self.encryption.decrypt(encyrpted_value, schema_version, salt))
        self.assertEqual(str(error.exception), "database exception Unexpected type.")
        mock_get_secret_key.assert_called_once()
        mock_decrypt_value.assert_not_called()

    @patch.object(Encryption, "get_secret_key", new_callable=AsyncMock)
    @patch.object(Encryption, "_decrypt_value")
    def test_decrypt_decrypt_value_raises(
        self, mock_decrypt_value, mock_get_secret_key
    ):
        """Method get_secret_key raises error."""
        mock_decrypt_value.side_effect = TypeError(
            "A bytes-like object is required, not 'str'"
        )
        with self.assertRaises(Exception) as error:
            asyncio.run(self.encryption.decrypt(encyrpted_value, schema_version, salt))
        self.assertEqual(
            str(error.exception), "A bytes-like object is required, not 'str'"
        )
        mock_get_secret_key.assert_called_once()
        mock_decrypt_value.assert_called_once_with(
            encyrpted_value, schema_version, salt
        )

    def test_join_keys_string_key(self):
        """key is string."""
        string_key = "sample key"
        result = self.encryption._join_keys(string_key, secret_key)
        self.assertEqual(result, joined_key)
        self.assertTrue(isinstance(result, bytes))

    def test_join_keys_bytes_key(self):
        """key is bytes."""
        bytes_key = b"sample key"
        result = self.encryption._join_keys(bytes_key, secret_key)
        self.assertEqual(result, joined_key)
        self.assertTrue(isinstance(result, bytes))
        self.assertEqual(len(result.decode("unicode_escape")), 32)

    def test_join_keys_int_key(self):
        """key is int."""
        int_key = 923
        with self.assertRaises(Exception) as error:
            self.encryption._join_keys(int_key, None)
        self.assertEqual(str(error.exception), "'int' object is not iterable")

    def test_join_keys_none_secret_key(self):
        """key is as bytes and secret key is None."""
        bytes_key = b"sample key"
        result = self.encryption._join_keys(bytes_key, None)
        self.assertEqual(
            result,
            b"sample key\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )
        self.assertTrue(isinstance(result, bytes))
        self.assertEqual(len(result.decode("unicode_escape")), 32)

    def test_join_keys_none_key_none_secret_key(self):
        """key is None and secret key is None."""
        with self.assertRaises(Exception) as error:
            self.encryption._join_keys(None, None)
        self.assertEqual(str(error.exception), "'NoneType' object is not iterable")

    def test_join_keys_none_key(self):
        """key is None and secret key exists."""
        with self.assertRaises(Exception) as error:
            self.encryption._join_keys(None, secret_key)
        self.assertEqual(str(error.exception), "'NoneType' object is not iterable")

    @patch.object(Encryption, "_join_keys")
    def test_join_secret_key_string_sample_key(self, mock_join_keys):
        """key is None and secret key exists as string."""
        update_key = "sample key"
        mock_join_keys.return_value = joined_key
        result = self.encryption._join_secret_key(update_key)
        self.assertEqual(result, joined_key)
        self.assertTrue(isinstance(result, bytes))
        mock_join_keys.assert_called_once_with(update_key, secret_key)

    @patch.object(Encryption, "_join_keys")
    def test_join_secret_key_byte_sample_key(self, mock_join_keys):
        """key is None and secret key exists as bytes."""
        update_key = b"sample key"
        mock_join_keys.return_value = joined_key
        result = self.encryption._join_secret_key(update_key)
        self.assertEqual(result, joined_key)
        self.assertTrue(isinstance(result, bytes))
        mock_join_keys.assert_called_once_with(update_key, secret_key)

    @patch.object(Encryption, "_join_keys")
    def test_join_secret_key_join_keys_raises(self, mock_join_keys):
        """Method _join_secret_key raises."""
        update_key = 3434
        mock_join_keys.side_effect = TypeError("'int' object is not iterable")
        with self.assertRaises(Exception) as error:
            self.encryption._join_secret_key(update_key)
        self.assertEqual(str(error.exception), "'int' object is not iterable")
        mock_join_keys.assert_called_once_with(update_key, secret_key)

    @patch.object(Encryption, "_join_keys")
    def test_get_secret_key_exists(self, mock_join_keys):
        """secret_key exists."""
        self.encryption._secret_key = secret_key
        asyncio.run(self.encryption.get_secret_key())
        self.assertEqual(self.encryption.secret_key, secret_key)
        mock_join_keys.assert_not_called()

    @patch.object(Encryption, "_join_keys")
    @patch("osm_common.dbbase.b64decode")
    def test_get_secret_key_not_exist_database_key_exist(
        self, mock_b64decode, mock_join_keys
    ):
        """secret_key does not exist, database key exists."""
        self.encryption._secret_key = None
        self.encryption._admin_collection.find_one.return_value = None
        self.encryption._config = {"database_commonkey": "osm_new_key"}
        mock_join_keys.return_value = joined_key
        asyncio.run(self.encryption.get_secret_key())
        self.assertEqual(self.encryption.secret_key, joined_key)
        self.assertEqual(mock_join_keys.call_count, 1)
        mock_b64decode.assert_not_called()

    @patch.object(Encryption, "_join_keys")
    @patch("osm_common.dbbase.b64decode")
    def test_get_secret_key_not_exist_with_database_key_version_data_exist_without_serial(
        self, mock_b64decode, mock_join_keys
    ):
        """secret_key does not exist, database key exists."""
        self.encryption._secret_key = None
        self.encryption._admin_collection.find_one.return_value = {"version": "1.0"}
        self.encryption._config = {"database_commonkey": "osm_new_key"}
        mock_join_keys.return_value = joined_key
        asyncio.run(self.encryption.get_secret_key())
        self.assertEqual(self.encryption.secret_key, joined_key)
        self.assertEqual(mock_join_keys.call_count, 1)
        mock_b64decode.assert_not_called()
        self.encryption._admin_collection.find_one.assert_called_once_with(
            {"_id": "version"}
        )
        _call_mock_join_keys = mock_join_keys.call_args_list
        self.assertEqual(_call_mock_join_keys[0].args, ("osm_new_key", None))

    @patch.object(Encryption, "_join_keys")
    @patch("osm_common.dbbase.b64decode")
    def test_get_secret_key_not_exist_with_database_key_version_data_exist_with_serial(
        self, mock_b64decode, mock_join_keys
    ):
        """secret_key does not exist, database key exists, version and serial exist
        in admin collection."""
        self.encryption._secret_key = None
        self.encryption._admin_collection.find_one.return_value = {
            "version": "1.0",
            "serial": serial_bytes,
        }
        self.encryption._config = {"database_commonkey": "osm_new_key"}
        mock_join_keys.side_effect = [secret_key, joined_key]
        mock_b64decode.return_value = base64_decoded_serial
        asyncio.run(self.encryption.get_secret_key())
        self.assertEqual(self.encryption.secret_key, joined_key)
        self.assertEqual(mock_join_keys.call_count, 2)
        mock_b64decode.assert_called_once_with(serial_bytes)
        self.encryption._admin_collection.find_one.assert_called_once_with(
            {"_id": "version"}
        )
        _call_mock_join_keys = mock_join_keys.call_args_list
        self.assertEqual(_call_mock_join_keys[0].args, ("osm_new_key", None))
        self.assertEqual(
            _call_mock_join_keys[1].args, (base64_decoded_serial, secret_key)
        )

    @patch.object(Encryption, "_join_keys")
    @patch("osm_common.dbbase.b64decode")
    def test_get_secret_key_join_keys_raises(self, mock_b64decode, mock_join_keys):
        """Method _join_keys raises."""
        self.encryption._secret_key = None
        self.encryption._admin_collection.find_one.return_value = {
            "version": "1.0",
            "serial": serial_bytes,
        }
        self.encryption._config = {"database_commonkey": "osm_new_key"}
        mock_join_keys.side_effect = DbException("Invalid data type.")
        with self.assertRaises(Exception) as error:
            asyncio.run(self.encryption.get_secret_key())
        self.assertEqual(str(error.exception), "database exception Invalid data type.")
        self.assertEqual(mock_join_keys.call_count, 1)
        check_if_assert_not_called(
            [mock_b64decode, self.encryption._admin_collection.find_one]
        )
        _call_mock_join_keys = mock_join_keys.call_args_list
        self.assertEqual(_call_mock_join_keys[0].args, ("osm_new_key", None))

    @patch.object(Encryption, "_join_keys")
    @patch("osm_common.dbbase.b64decode")
    def test_get_secret_key_b64decode_raises(self, mock_b64decode, mock_join_keys):
        """Method b64decode raises."""
        self.encryption._secret_key = None
        self.encryption._admin_collection.find_one.return_value = {
            "version": "1.0",
            "serial": base64_decoded_serial,
        }
        self.encryption._config = {"database_commonkey": "osm_new_key"}
        mock_join_keys.return_value = secret_key
        mock_b64decode.side_effect = TypeError(
            "A bytes-like object is required, not 'str'"
        )
        with self.assertRaises(Exception) as error:
            asyncio.run(self.encryption.get_secret_key())
        self.assertEqual(
            str(error.exception), "A bytes-like object is required, not 'str'"
        )
        self.assertEqual(self.encryption.secret_key, None)
        self.assertEqual(mock_join_keys.call_count, 1)
        mock_b64decode.assert_called_once_with(base64_decoded_serial)
        self.encryption._admin_collection.find_one.assert_called_once_with(
            {"_id": "version"}
        )
        _call_mock_join_keys = mock_join_keys.call_args_list
        self.assertEqual(_call_mock_join_keys[0].args, ("osm_new_key", None))

    @patch.object(Encryption, "_join_keys")
    @patch("osm_common.dbbase.b64decode")
    def test_get_secret_key_admin_collection_find_one_raises(
        self, mock_b64decode, mock_join_keys
    ):
        """admin_collection find_one raises."""
        self.encryption._secret_key = None
        self.encryption._admin_collection.find_one.side_effect = DbException(
            "Connection failed."
        )
        self.encryption._config = {"database_commonkey": "osm_new_key"}
        mock_join_keys.return_value = secret_key
        with self.assertRaises(Exception) as error:
            asyncio.run(self.encryption.get_secret_key())
        self.assertEqual(str(error.exception), "database exception Connection failed.")
        self.assertEqual(self.encryption.secret_key, None)
        self.assertEqual(mock_join_keys.call_count, 1)
        mock_b64decode.assert_not_called()
        self.encryption._admin_collection.find_one.assert_called_once_with(
            {"_id": "version"}
        )
        _call_mock_join_keys = mock_join_keys.call_args_list
        self.assertEqual(_call_mock_join_keys[0].args, ("osm_new_key", None))

    def test_encrypt_decrypt_with_schema_version_1_1_with_salt(self):
        """Encrypt and decrypt with schema version 1.1, salt exists."""
        encrypted_msg = asyncio.run(
            self.encryption.encrypt(value, schema_version, salt)
        )
        decrypted_msg = asyncio.run(
            self.encryption.decrypt(encrypted_msg, schema_version, salt)
        )
        self.assertEqual(value, decrypted_msg)

    def test_encrypt_decrypt_with_schema_version_1_0_with_salt(self):
        """Encrypt and decrypt with schema version 1.0, salt exists."""
        schema_version = "1.0"
        encrypted_msg = asyncio.run(
            self.encryption.encrypt(value, schema_version, salt)
        )
        decrypted_msg = asyncio.run(
            self.encryption.decrypt(encrypted_msg, schema_version, salt)
        )
        self.assertEqual(value, decrypted_msg)

    def test_encrypt_decrypt_with_schema_version_1_1_without_salt(self):
        """Encrypt and decrypt with schema version 1.1, without salt."""
        salt = None
        with self.assertRaises(Exception) as error:
            asyncio.run(self.encryption.encrypt(value, schema_version, salt))
        self.assertEqual(str(error.exception), "'NoneType' object is not iterable")


class TestDeepUpdate(unittest.TestCase):
    def test_update_dict(self):
        # Original, patch, expected result
        TEST = (
            ({"a": "b"}, {"a": "c"}, {"a": "c"}),
            ({"a": "b"}, {"b": "c"}, {"a": "b", "b": "c"}),
            ({"a": "b"}, {"a": None}, {}),
            ({"a": "b", "b": "c"}, {"a": None}, {"b": "c"}),
            ({"a": ["b"]}, {"a": "c"}, {"a": "c"}),
            ({"a": "c"}, {"a": ["b"]}, {"a": ["b"]}),
            ({"a": {"b": "c"}}, {"a": {"b": "d", "c": None}}, {"a": {"b": "d"}}),
            ({"a": [{"b": "c"}]}, {"a": [1]}, {"a": [1]}),
            ({1: ["a", "b"]}, {1: ["c", "d"]}, {1: ["c", "d"]}),
            ({1: {"a": "b"}}, {1: ["c"]}, {1: ["c"]}),
            ({1: {"a": "foo"}}, {1: None}, {}),
            ({1: {"a": "foo"}}, {1: "bar"}, {1: "bar"}),
            ({"e": None}, {"a": 1}, {"e": None, "a": 1}),
            ({1: [1, 2]}, {1: {"a": "b", "c": None}}, {1: {"a": "b"}}),
            ({}, {"a": {"bb": {"ccc": None}}}, {"a": {"bb": {}}}),
        )
        for t in TEST:
            deep_update(t[0], t[1])
            self.assertEqual(t[0], t[2])
        # test deepcopy is done. So that original dictionary does not reference the pach
        test_original = {1: {"a": "b"}}
        test_patch = {1: {"c": {"d": "e"}}}
        test_result = {1: {"a": "b", "c": {"d": "e"}}}
        deep_update(test_original, test_patch)
        self.assertEqual(test_original, test_result)
        test_patch[1]["c"]["f"] = "edition of patch, must not modify original"
        self.assertEqual(test_original, test_result)

    def test_update_array(self):
        # This TEST contains a list with the the Original, patch, and expected result
        TEST = (
            # delete all instances of "a"/"d"
            ({"A": ["a", "b", "a"]}, {"A": {"$a": None}}, {"A": ["b"]}),
            ({"A": ["a", "b", "a"]}, {"A": {"$d": None}}, {"A": ["a", "b", "a"]}),
            # delete and insert at 0
            (
                {"A": ["a", "b", "c"]},
                {"A": {"$b": None, "$+[0]": "b"}},
                {"A": ["b", "a", "c"]},
            ),
            # delete and edit
            (
                {"A": ["a", "b", "a"]},
                {"A": {"$a": None, "$[1]": {"c": "d"}}},
                {"A": [{"c": "d"}]},
            ),
            # insert if not exist
            ({"A": ["a", "b", "c"]}, {"A": {"$+b": "b"}}, {"A": ["a", "b", "c"]}),
            ({"A": ["a", "b", "c"]}, {"A": {"$+d": "f"}}, {"A": ["a", "b", "c", "f"]}),
            # edit by filter
            (
                {"A": ["a", "b", "a"]},
                {"A": {"$b": {"c": "d"}}},
                {"A": ["a", {"c": "d"}, "a"]},
            ),
            (
                {"A": ["a", "b", "a"]},
                {"A": {"$b": None, "$+[0]": "b", "$+": "c"}},
                {"A": ["b", "a", "a", "c"]},
            ),
            ({"A": ["a", "b", "a"]}, {"A": {"$c": None}}, {"A": ["a", "b", "a"]}),
            # index deletion out of range
            ({"A": ["a", "b", "a"]}, {"A": {"$[5]": None}}, {"A": ["a", "b", "a"]}),
            # nested array->dict
            (
                {"A": ["a", "b", {"id": "1", "c": {"d": 2}}]},
                {"A": {"$id: '1'": {"h": None, "c": {"d": "e", "f": "g"}}}},
                {"A": ["a", "b", {"id": "1", "c": {"d": "e", "f": "g"}}]},
            ),
            (
                {"A": [{"id": 1, "c": {"d": 2}}, {"id": 1, "c": {"f": []}}]},
                {"A": {"$id: 1": {"h": None, "c": {"d": "e", "f": "g"}}}},
                {
                    "A": [
                        {"id": 1, "c": {"d": "e", "f": "g"}},
                        {"id": 1, "c": {"d": "e", "f": "g"}},
                    ]
                },
            ),
            # nested array->array
            (
                {"A": ["a", "b", ["a", "b"]]},
                {"A": {"$b": None, "$[2]": {"$b": {}, "$+": "c"}}},
                {"A": ["a", ["a", {}, "c"]]},
            ),
            # types str and int different, so not found
            (
                {"A": ["a", {"id": "1", "c": "d"}]},
                {"A": {"$id: 1": {"c": "e"}}},
                {"A": ["a", {"id": "1", "c": "d"}]},
            ),
        )
        for t in TEST:
            print(t)
            deep_update(t[0], t[1])
            self.assertEqual(t[0], t[2])

    def test_update_badformat(self):
        # This TEST contains original, incorrect patch and #TODO text that must be present
        TEST = (
            # conflict, index 0 is edited twice
            ({"A": ["a", "b", "a"]}, {"A": {"$a": None, "$[0]": {"c": "d"}}}),
            # conflict, two insertions at same index
            ({"A": ["a", "b", "a"]}, {"A": {"$[1]": "c", "$[-2]": "d"}}),
            ({"A": ["a", "b", "a"]}, {"A": {"$[1]": "c", "$[+1]": "d"}}),
            # bad format keys with and without $
            ({"A": ["a", "b", "a"]}, {"A": {"$b": {"c": "d"}, "c": 3}}),
            # bad format empty $ and yaml incorrect
            ({"A": ["a", "b", "a"]}, {"A": {"$": 3}}),
            ({"A": ["a", "b", "a"]}, {"A": {"$a: b: c": 3}}),
            ({"A": ["a", "b", "a"]}, {"A": {"$a: b, c: d": 3}}),
            # insertion of None
            ({"A": ["a", "b", "a"]}, {"A": {"$+": None}}),
            # Not found, insertion of None
            ({"A": ["a", "b", "a"]}, {"A": {"$+c": None}}),
            # index edition out of range
            ({"A": ["a", "b", "a"]}, {"A": {"$[5]": 6}}),
            # conflict, two editions on index 2
            (
                {"A": ["a", {"id": "1", "c": "d"}]},
                {"A": {"$id: '1'": {"c": "e"}, "$c: d": {"c": "f"}}},
            ),
        )
        for t in TEST:
            print(t)
            self.assertRaises(DbException, deep_update, t[0], t[1])
            try:
                deep_update(t[0], t[1])
            except DbException as e:
                print(e)


if __name__ == "__main__":
    unittest.main()
