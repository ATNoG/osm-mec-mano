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
import http

from osm_common.msgbase import MsgBase, MsgException
import pytest


def exception_message(message):
    return "messaging exception " + message


@pytest.fixture
def msg_base():
    return MsgBase()


def test_constructor():
    msgbase = MsgBase()
    assert msgbase is not None
    assert isinstance(msgbase, MsgBase)


def test_connect(msg_base):
    msg_base.connect(None)


def test_disconnect(msg_base):
    msg_base.disconnect()


def test_write(msg_base):
    with pytest.raises(MsgException) as excinfo:
        msg_base.write("test", "test", "test")
    assert str(excinfo.value).startswith(
        exception_message("Method 'write' not implemented")
    )
    assert excinfo.value.http_code == http.HTTPStatus.INTERNAL_SERVER_ERROR


def test_read(msg_base):
    with pytest.raises(MsgException) as excinfo:
        msg_base.read("test")
    assert str(excinfo.value).startswith(
        exception_message("Method 'read' not implemented")
    )
    assert excinfo.value.http_code == http.HTTPStatus.INTERNAL_SERVER_ERROR


def test_aiowrite(msg_base):
    with pytest.raises(MsgException) as excinfo:
        asyncio.run(msg_base.aiowrite("test", "test", "test"))
    assert str(excinfo.value).startswith(
        exception_message("Method 'aiowrite' not implemented")
    )
    assert excinfo.value.http_code == http.HTTPStatus.INTERNAL_SERVER_ERROR


def test_aioread(msg_base):
    with pytest.raises(MsgException) as excinfo:
        asyncio.run(msg_base.aioread("test"))
    assert str(excinfo.value).startswith(
        exception_message("Method 'aioread' not implemented")
    )
    assert excinfo.value.http_code == http.HTTPStatus.INTERNAL_SERVER_ERROR
