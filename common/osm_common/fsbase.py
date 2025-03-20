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


class FsException(Exception):
    def __init__(self, message, http_code=HTTPStatus.INTERNAL_SERVER_ERROR):
        self.http_code = http_code
        Exception.__init__(self, "storage exception " + message)


class FsBase(object):
    def __init__(self, logger_name="fs", lock=False):
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

    def get_params(self):
        return {}

    def fs_connect(self, config):
        pass

    def fs_disconnect(self):
        pass

    def mkdir(self, folder):
        raise FsException("Method 'mkdir' not implemented")

    def dir_rename(self, src, dst):
        raise FsException("Method 'dir_rename' not implemented")

    def dir_ls(self, storage):
        raise FsException("Method 'dir_ls' not implemented")

    def file_exists(self, storage):
        raise FsException("Method 'file_exists' not implemented")

    def file_size(self, storage):
        raise FsException("Method 'file_size' not implemented")

    def file_extract(self, tar_object, path):
        raise FsException("Method 'file_extract' not implemented")

    def file_open(self, storage, mode):
        raise FsException("Method 'file_open' not implemented")

    def file_delete(self, storage, ignore_non_exist=False):
        raise FsException("Method 'file_delete' not implemented")

    def sync(self, from_path=None):
        raise FsException("Method 'sync' not implemented")

    def reverse_sync(self, from_path):
        raise FsException("Method 'reverse_sync' not implemented")
