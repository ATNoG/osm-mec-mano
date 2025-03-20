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
import os
from shutil import rmtree
import tarfile
import zipfile

from osm_common.fsbase import FsBase, FsException

__author__ = "Alfonso Tierno <alfonso.tiernosepulveda@telefonica.com>"


class FsLocal(FsBase):
    def __init__(self, logger_name="fs", lock=False):
        super().__init__(logger_name, lock)
        self.path = None

    def get_params(self):
        return {"fs": "local", "path": self.path}

    def fs_connect(self, config):
        try:
            if "logger_name" in config:
                self.logger = logging.getLogger(config["logger_name"])
            self.path = config["path"]
            if not self.path.endswith("/"):
                self.path += "/"
            if not os.path.exists(self.path):
                raise FsException(
                    "Invalid configuration param at '[storage]': path '{}' does not exist".format(
                        config["path"]
                    )
                )
        except FsException:
            raise
        except Exception as e:  # TODO refine
            raise FsException(str(e))

    def fs_disconnect(self):
        pass  # TODO

    def mkdir(self, folder):
        """
        Creates a folder or parent object location
        :param folder:
        :return: None or raises and exception
        """
        try:
            os.mkdir(self.path + folder)
        except FileExistsError:  # make it idempotent
            pass
        except Exception as e:
            raise FsException(str(e), http_code=HTTPStatus.INTERNAL_SERVER_ERROR)

    def dir_rename(self, src, dst):
        """
        Rename one directory name. If dst exist, it replaces (deletes) existing directory
        :param src: source directory
        :param dst: destination directory
        :return: None or raises and exception
        """
        try:
            if os.path.exists(self.path + dst):
                rmtree(self.path + dst)

            os.rename(self.path + src, self.path + dst)

        except Exception as e:
            raise FsException(str(e), http_code=HTTPStatus.INTERNAL_SERVER_ERROR)

    def file_exists(self, storage, mode=None):
        """
        Indicates if "storage" file exist
        :param storage: can be a str or a str list
        :param mode: can be 'file' exist as a regular file; 'dir' exists as a directory or; 'None' just exists
        :return: True, False
        """
        if isinstance(storage, str):
            f = storage
        else:
            f = "/".join(storage)
        if os.path.exists(self.path + f):
            if not mode:
                return True
            if mode == "file" and os.path.isfile(self.path + f):
                return True
            if mode == "dir" and os.path.isdir(self.path + f):
                return True
        return False

    def file_size(self, storage):
        """
        return file size
        :param storage: can be a str or a str list
        :return: file size
        """
        if isinstance(storage, str):
            f = storage
        else:
            f = "/".join(storage)
        return os.path.getsize(self.path + f)

    def file_extract(self, compressed_object, path):
        """
        extract a tar file
        :param compressed_object: object of type tar or zip
        :param path: can be a str or a str list, or a tar object where to extract the tar_object
        :return: None
        """
        if isinstance(path, str):
            f = self.path + path
        else:
            f = self.path + "/".join(path)

        if type(compressed_object) is tarfile.TarFile:
            compressed_object.extractall(path=f)
        elif (
            type(compressed_object) is zipfile.ZipFile
        ):  # Just a check to know if this works with both tar and zip
            compressed_object.extractall(path=f)

    def file_open(self, storage, mode):
        """
        Open a file
        :param storage: can be a str or list of str
        :param mode: file mode
        :return: file object
        """
        try:
            if isinstance(storage, str):
                f = storage
            else:
                f = "/".join(storage)
            return open(self.path + f, mode)
        except FileNotFoundError:
            raise FsException(
                "File {} does not exist".format(f), http_code=HTTPStatus.NOT_FOUND
            )
        except IOError:
            raise FsException(
                "File {} cannot be opened".format(f), http_code=HTTPStatus.BAD_REQUEST
            )

    def dir_ls(self, storage):
        """
        return folder content
        :param storage: can be a str or list of str
        :return: folder content
        """
        try:
            if isinstance(storage, str):
                f = storage
            else:
                f = "/".join(storage)
            return os.listdir(self.path + f)
        except NotADirectoryError:
            raise FsException(
                "File {} does not exist".format(f), http_code=HTTPStatus.NOT_FOUND
            )
        except IOError:
            raise FsException(
                "File {} cannot be opened".format(f), http_code=HTTPStatus.BAD_REQUEST
            )

    def file_delete(self, storage, ignore_non_exist=False):
        """
        Delete storage content recursively
        :param storage: can be a str or list of str
        :param ignore_non_exist: not raise exception if storage does not exist
        :return: None
        """
        try:
            if isinstance(storage, str):
                f = self.path + storage
            else:
                f = self.path + "/".join(storage)
            if os.path.exists(f):
                rmtree(f)
            elif not ignore_non_exist:
                raise FsException(
                    "File {} does not exist".format(storage),
                    http_code=HTTPStatus.NOT_FOUND,
                )
        except (IOError, PermissionError) as e:
            raise FsException(
                "File {} cannot be deleted: {}".format(f, e),
                http_code=HTTPStatus.INTERNAL_SERVER_ERROR,
            )

    def sync(self, from_path=None):
        pass  # Not needed in fslocal

    def reverse_sync(self, from_path):
        pass  # Not needed in fslocal
