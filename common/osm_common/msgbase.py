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

from http import HTTPStatus
import logging
from threading import Lock

from osm_common.common_utils import FakeLock

__author__ = "Alfonso Tierno <alfonso.tiernosepulveda@telefonica.com>"


class MsgException(Exception):
    """
    Base Exception class for all msgXXXX exceptions
    """

    def __init__(self, message, http_code=HTTPStatus.SERVICE_UNAVAILABLE):
        """
        General exception
        :param message:  descriptive text
        :param http_code: <http.HTTPStatus> type. It contains ".value" (http error code) and ".name" (http error name
        """
        self.http_code = http_code
        Exception.__init__(self, "messaging exception " + message)


class MsgBase(object):
    """
    Base class for all msgXXXX classes
    """

    def __init__(self, logger_name="msg", lock=False):
        """
        Constructor of FsBase
        :param logger_name: logging name
        :param lock: Used to protect simultaneous access to the same instance class by several threads:
            False, None: Do not protect, this object will only be accessed by one thread
            True: This object needs to be protected by several threads accessing.
            Lock object. Use thi Lock for the threads access protection
        """
        self.logger = logging.getLogger(logger_name)
        if not lock:
            self.lock = FakeLock()
        elif lock is True:
            self.lock = Lock()
        elif isinstance(lock, Lock):
            self.lock = lock
        else:
            raise ValueError("lock parameter must be a Lock class or boolean")

    def connect(self, config):
        pass

    def disconnect(self):
        pass

    def write(self, topic, key, msg):
        raise MsgException(
            "Method 'write' not implemented", http_code=HTTPStatus.INTERNAL_SERVER_ERROR
        )

    def read(self, topic):
        raise MsgException(
            "Method 'read' not implemented", http_code=HTTPStatus.INTERNAL_SERVER_ERROR
        )

    async def aiowrite(self, topic, key, msg):
        raise MsgException(
            "Method 'aiowrite' not implemented",
            http_code=HTTPStatus.INTERNAL_SERVER_ERROR,
        )

    async def aioread(
        self, topic, callback=None, aiocallback=None, group_id=None, **kwargs
    ):
        raise MsgException(
            "Method 'aioread' not implemented",
            http_code=HTTPStatus.INTERNAL_SERVER_ERROR,
        )
