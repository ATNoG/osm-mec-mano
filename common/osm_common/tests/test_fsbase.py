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

import http

from osm_common.fsbase import FsBase, FsException
import pytest


def exception_message(message):
    return "storage exception " + message


@pytest.fixture
def fs_base():
    return FsBase()


def test_constructor():
    fs_base = FsBase()
    assert fs_base is not None
    assert isinstance(fs_base, FsBase)


def test_get_params(fs_base):
    params = fs_base.get_params()
    assert isinstance(params, dict)
    assert len(params) == 0


def test_fs_connect(fs_base):
    fs_base.fs_connect(None)


def test_fs_disconnect(fs_base):
    fs_base.fs_disconnect()


def test_mkdir(fs_base):
    with pytest.raises(FsException) as excinfo:
        fs_base.mkdir(None)
    assert str(excinfo.value).startswith(
        exception_message("Method 'mkdir' not implemented")
    )
    assert excinfo.value.http_code == http.HTTPStatus.INTERNAL_SERVER_ERROR


def test_file_exists(fs_base):
    with pytest.raises(FsException) as excinfo:
        fs_base.file_exists(None)
    assert str(excinfo.value).startswith(
        exception_message("Method 'file_exists' not implemented")
    )
    assert excinfo.value.http_code == http.HTTPStatus.INTERNAL_SERVER_ERROR


def test_file_size(fs_base):
    with pytest.raises(FsException) as excinfo:
        fs_base.file_size(None)
    assert str(excinfo.value).startswith(
        exception_message("Method 'file_size' not implemented")
    )
    assert excinfo.value.http_code == http.HTTPStatus.INTERNAL_SERVER_ERROR


def test_file_extract(fs_base):
    with pytest.raises(FsException) as excinfo:
        fs_base.file_extract(None, None)
    assert str(excinfo.value).startswith(
        exception_message("Method 'file_extract' not implemented")
    )
    assert excinfo.value.http_code == http.HTTPStatus.INTERNAL_SERVER_ERROR


def test_file_open(fs_base):
    with pytest.raises(FsException) as excinfo:
        fs_base.file_open(None, None)
    assert str(excinfo.value).startswith(
        exception_message("Method 'file_open' not implemented")
    )
    assert excinfo.value.http_code == http.HTTPStatus.INTERNAL_SERVER_ERROR


def test_file_delete(fs_base):
    with pytest.raises(FsException) as excinfo:
        fs_base.file_delete(None, None)
    assert str(excinfo.value).startswith(
        exception_message("Method 'file_delete' not implemented")
    )
    assert excinfo.value.http_code == http.HTTPStatus.INTERNAL_SERVER_ERROR
