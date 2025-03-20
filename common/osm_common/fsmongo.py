# Copyright 2019 Canonical
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
# contact: eduardo.sousa@canonical.com
##
import datetime
import errno
from http import HTTPStatus
from io import BytesIO, StringIO
import logging
import os
import tarfile
import zipfile

from gridfs import errors, GridFSBucket
from osm_common.fsbase import FsBase, FsException
from pymongo import MongoClient


__author__ = "Eduardo Sousa <eduardo.sousa@canonical.com>"


class GridByteStream(BytesIO):
    def __init__(self, filename, fs, mode):
        BytesIO.__init__(self)
        self._id = None
        self.filename = filename
        self.fs = fs
        self.mode = mode
        self.file_type = "file"  # Set "file" as default file_type

        self.__initialize__()

    def __initialize__(self):
        grid_file = None

        cursor = self.fs.find({"filename": self.filename})

        for requested_file in cursor:
            exception_file = next(cursor, None)

            if exception_file:
                raise FsException(
                    "Multiple files found", http_code=HTTPStatus.INTERNAL_SERVER_ERROR
                )

            if requested_file.metadata["type"] in ("file", "sym"):
                grid_file = requested_file
                self.file_type = requested_file.metadata["type"]
            else:
                raise FsException(
                    "Type isn't file", http_code=HTTPStatus.INTERNAL_SERVER_ERROR
                )

        if grid_file:
            self._id = grid_file._id
            self.fs.download_to_stream(self._id, self)

            if "r" in self.mode:
                self.seek(0, 0)

    def close(self):
        if "r" in self.mode:
            super(GridByteStream, self).close()
            return

        if self._id:
            self.fs.delete(self._id)

        cursor = self.fs.find(
            {"filename": self.filename.split("/")[0], "metadata": {"type": "dir"}}
        )

        parent_dir = next(cursor, None)

        if not parent_dir:
            parent_dir_name = self.filename.split("/")[0]
            self.filename = self.filename.replace(
                parent_dir_name, parent_dir_name[:-1], 1
            )

        self.seek(0, 0)
        if self._id:
            self.fs.upload_from_stream_with_id(
                self._id, self.filename, self, metadata={"type": self.file_type}
            )
        else:
            self.fs.upload_from_stream(
                self.filename, self, metadata={"type": self.file_type}
            )
        super(GridByteStream, self).close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()


class GridStringStream(StringIO):
    def __init__(self, filename, fs, mode):
        StringIO.__init__(self)
        self._id = None
        self.filename = filename
        self.fs = fs
        self.mode = mode
        self.file_type = "file"  # Set "file" as default file_type

        self.__initialize__()

    def __initialize__(self):
        grid_file = None

        cursor = self.fs.find({"filename": self.filename})

        for requested_file in cursor:
            exception_file = next(cursor, None)

            if exception_file:
                raise FsException(
                    "Multiple files found", http_code=HTTPStatus.INTERNAL_SERVER_ERROR
                )

            if requested_file.metadata["type"] in ("file", "dir"):
                grid_file = requested_file
                self.file_type = requested_file.metadata["type"]
            else:
                raise FsException(
                    "File type isn't file", http_code=HTTPStatus.INTERNAL_SERVER_ERROR
                )

        if grid_file:
            stream = BytesIO()
            self._id = grid_file._id
            self.fs.download_to_stream(self._id, stream)
            stream.seek(0)
            self.write(stream.read().decode("utf-8"))
            stream.close()

            if "r" in self.mode:
                self.seek(0, 0)

    def close(self):
        if "r" in self.mode:
            super(GridStringStream, self).close()
            return

        if self._id:
            self.fs.delete(self._id)

        cursor = self.fs.find(
            {"filename": self.filename.split("/")[0], "metadata": {"type": "dir"}}
        )

        parent_dir = next(cursor, None)

        if not parent_dir:
            parent_dir_name = self.filename.split("/")[0]
            self.filename = self.filename.replace(
                parent_dir_name, parent_dir_name[:-1], 1
            )

        self.seek(0, 0)
        stream = BytesIO()
        stream.write(self.read().encode("utf-8"))
        stream.seek(0, 0)
        if self._id:
            self.fs.upload_from_stream_with_id(
                self._id, self.filename, stream, metadata={"type": self.file_type}
            )
        else:
            self.fs.upload_from_stream(
                self.filename, stream, metadata={"type": self.file_type}
            )
        stream.close()
        super(GridStringStream, self).close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()


class FsMongo(FsBase):
    def __init__(self, logger_name="fs", lock=False):
        super().__init__(logger_name, lock)
        self.path = None
        self.client = None
        self.fs = None

    def __update_local_fs(self, from_path=None):
        dir_cursor = self.fs.find({"metadata.type": "dir"}, no_cursor_timeout=True)

        valid_paths = []

        for directory in dir_cursor:
            if from_path and not directory.filename.startswith(from_path):
                continue
            self.logger.debug("Making dir {}".format(self.path + directory.filename))
            os.makedirs(self.path + directory.filename, exist_ok=True)
            valid_paths.append(self.path + directory.filename)

        file_cursor = self.fs.find(
            {"metadata.type": {"$in": ["file", "sym"]}}, no_cursor_timeout=True
        )

        for writing_file in file_cursor:
            if from_path and not writing_file.filename.startswith(from_path):
                continue
            file_path = self.path + writing_file.filename

            if writing_file.metadata["type"] == "sym":
                with BytesIO() as b:
                    self.fs.download_to_stream(writing_file._id, b)
                    b.seek(0)
                    link = b.read().decode("utf-8")

                try:
                    self.logger.debug("Sync removing {}".format(file_path))
                    os.remove(file_path)
                except OSError as e:
                    if e.errno != errno.ENOENT:
                        # This is probably permission denied or worse
                        raise
                os.symlink(
                    link, os.path.realpath(os.path.normpath(os.path.abspath(file_path)))
                )
            else:
                folder = os.path.dirname(file_path)
                if folder not in valid_paths:
                    self.logger.debug("Sync local directory {}".format(file_path))
                    os.makedirs(folder, exist_ok=True)
                with open(file_path, "wb+") as file_stream:
                    self.logger.debug("Sync download {}".format(file_path))
                    self.fs.download_to_stream(writing_file._id, file_stream)
                if "permissions" in writing_file.metadata:
                    os.chmod(file_path, writing_file.metadata["permissions"])

    def get_params(self):
        return {"fs": "mongo", "path": self.path}

    def fs_connect(self, config):
        try:
            if "logger_name" in config:
                self.logger = logging.getLogger(config["logger_name"])
            if "path" in config:
                self.path = config["path"]
            else:
                raise FsException('Missing parameter "path"')
            if not self.path.endswith("/"):
                self.path += "/"
            if not os.path.exists(self.path):
                raise FsException(
                    "Invalid configuration param at '[storage]': path '{}' does not exist".format(
                        config["path"]
                    )
                )
            elif not os.access(self.path, os.W_OK):
                raise FsException(
                    "Invalid configuration param at '[storage]': path '{}' is not writable".format(
                        config["path"]
                    )
                )
            if all(key in config.keys() for key in ["uri", "collection"]):
                self.client = MongoClient(config["uri"])
                self.fs = GridFSBucket(self.client[config["collection"]])
            else:
                if "collection" not in config.keys():
                    raise FsException('Missing parameter "collection"')
                else:
                    raise FsException('Missing parameters: "uri"')
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
        :return: None or raises an exception
        """
        folder = folder.rstrip("/")
        try:
            self.fs.upload_from_stream(folder, BytesIO(), metadata={"type": "dir"})
        except errors.FileExists:  # make it idempotent
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
        dst = dst.rstrip("/")
        src = src.rstrip("/")

        try:
            dst_cursor = self.fs.find(
                {"filename": {"$regex": "^{}(/|$)".format(dst)}}, no_cursor_timeout=True
            )

            for dst_file in dst_cursor:
                self.fs.delete(dst_file._id)

            src_cursor = self.fs.find(
                {"filename": {"$regex": "^{}(/|$)".format(src)}}, no_cursor_timeout=True
            )

            for src_file in src_cursor:
                self.fs.rename(src_file._id, src_file.filename.replace(src, dst, 1))
        except Exception as e:
            raise FsException(str(e), http_code=HTTPStatus.INTERNAL_SERVER_ERROR)

    def file_exists(self, storage, mode=None):
        """
        Indicates if "storage" file exist
        :param storage: can be a str or a str list
        :param mode: can be 'file' exist as a regular file; 'dir' exists as a directory or; 'None' just exists
        :return: True, False
        """
        f = storage if isinstance(storage, str) else "/".join(storage)
        f = f.rstrip("/")

        cursor = self.fs.find({"filename": f})

        for requested_file in cursor:
            exception_file = next(cursor, None)

            if exception_file:
                raise FsException(
                    "Multiple files found", http_code=HTTPStatus.INTERNAL_SERVER_ERROR
                )

            self.logger.debug("Entry {} metadata {}".format(f, requested_file.metadata))

            # if no special mode is required just check it does exists
            if not mode:
                return True

            if requested_file.metadata["type"] == mode:
                return True

            if requested_file.metadata["type"] == "sym" and mode == "file":
                return True

        return False

    def file_size(self, storage):
        """
        return file size
        :param storage: can be a str or a str list
        :return: file size
        """
        f = storage if isinstance(storage, str) else "/".join(storage)
        f = f.rstrip("/")

        cursor = self.fs.find({"filename": f})

        for requested_file in cursor:
            exception_file = next(cursor, None)

            if exception_file:
                raise FsException(
                    "Multiple files found", http_code=HTTPStatus.INTERNAL_SERVER_ERROR
                )

            return requested_file.length

    def file_extract(self, compressed_object, path):
        """
        extract a tar file
        :param compressed_object: object of type tar or zip
        :param path: can be a str or a str list, or a tar object where to extract the tar_object
        :return: None
        """
        f = path if isinstance(path, str) else "/".join(path)
        f = f.rstrip("/")

        if type(compressed_object) is tarfile.TarFile:
            for member in compressed_object.getmembers():
                if member.isfile():
                    stream = compressed_object.extractfile(member)
                elif member.issym():
                    stream = BytesIO(member.linkname.encode("utf-8"))
                else:
                    stream = BytesIO()

                if member.isfile():
                    file_type = "file"
                elif member.issym():
                    file_type = "sym"
                else:
                    file_type = "dir"

                metadata = {"type": file_type, "permissions": member.mode}
                member.name = member.name.rstrip("/")

                self.logger.debug("Uploading {}/{}".format(f, member.name))
                self.fs.upload_from_stream(
                    f + "/" + member.name, stream, metadata=metadata
                )

                stream.close()
        elif type(compressed_object) is zipfile.ZipFile:
            for member in compressed_object.infolist():
                if member.is_dir():
                    stream = BytesIO()
                else:
                    stream = compressed_object.read(member)

                if member.is_dir():
                    file_type = "dir"
                else:
                    file_type = "file"

                metadata = {"type": file_type}
                member.filename = member.filename.rstrip("/")

                self.logger.debug("Uploading {}/{}".format(f, member.filename))
                self.fs.upload_from_stream(
                    f + "/" + member.filename, stream, metadata=metadata
                )

                if member.is_dir():
                    stream.close()

    def file_open(self, storage, mode):
        """
        Open a file
        :param storage: can be a str or list of str
        :param mode: file mode
        :return: file object
        """
        try:
            f = storage if isinstance(storage, str) else "/".join(storage)
            f = f.rstrip("/")

            if "b" in mode:
                return GridByteStream(f, self.fs, mode)
            else:
                return GridStringStream(f, self.fs, mode)
        except errors.NoFile:
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
            f = storage if isinstance(storage, str) else "/".join(storage)
            f = f.rstrip("/")

            files = []
            dir_cursor = self.fs.find({"filename": f})
            for requested_dir in dir_cursor:
                exception_dir = next(dir_cursor, None)

                if exception_dir:
                    raise FsException(
                        "Multiple directories found",
                        http_code=HTTPStatus.INTERNAL_SERVER_ERROR,
                    )

                if requested_dir.metadata["type"] != "dir":
                    raise FsException(
                        "File {} does not exist".format(f),
                        http_code=HTTPStatus.NOT_FOUND,
                    )

                if f.endswith("/"):
                    f = f[:-1]

                files_cursor = self.fs.find(
                    {"filename": {"$regex": "^{}/([^/])*".format(f)}}
                )
                for children_file in files_cursor:
                    files += [children_file.filename.replace(f + "/", "", 1)]

            return files
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
            f = storage if isinstance(storage, str) else "/".join(storage)
            f = f.rstrip("/")

            file_cursor = self.fs.find({"filename": f})
            found = False
            for requested_file in file_cursor:
                found = True
                exception_file = next(file_cursor, None)

                if exception_file:
                    self.logger.error(
                        "Cannot delete duplicate file: {} and {}".format(
                            requested_file.filename, exception_file.filename
                        )
                    )
                    raise FsException(
                        "Multiple files found",
                        http_code=HTTPStatus.INTERNAL_SERVER_ERROR,
                    )

                if requested_file.metadata["type"] == "dir":
                    dir_cursor = self.fs.find(
                        {"filename": {"$regex": "^{}/".format(f)}}
                    )

                    for tmp in dir_cursor:
                        self.logger.debug("Deleting {}".format(tmp.filename))
                        self.fs.delete(tmp._id)

                self.logger.debug("Deleting {}".format(requested_file.filename))
                self.fs.delete(requested_file._id)
            if not found and not ignore_non_exist:
                raise FsException(
                    "File {} does not exist".format(storage),
                    http_code=HTTPStatus.NOT_FOUND,
                )
        except IOError as e:
            raise FsException(
                "File {} cannot be deleted: {}".format(f, e),
                http_code=HTTPStatus.INTERNAL_SERVER_ERROR,
            )

    def sync(self, from_path=None):
        """
        Sync from FSMongo to local storage
        :param from_path: if supplied, only copy content from this path, not all
        :return: None
        """
        if from_path:
            if os.path.isabs(from_path):
                from_path = os.path.relpath(from_path, self.path)
        self.__update_local_fs(from_path=from_path)

    def _update_mongo_fs(self, from_path):
        os_path = self.path + from_path
        # Obtain list of files and dirs in filesystem
        members = []
        for root, dirs, files in os.walk(os_path):
            for folder in dirs:
                member = {"filename": os.path.join(root, folder), "type": "dir"}
                if os.path.islink(member["filename"]):
                    member["type"] = "sym"
                members.append(member)
            for file in files:
                filename = os.path.join(root, file)
                if os.path.islink(filename):
                    file_type = "sym"
                else:
                    file_type = "file"
                member = {"filename": os.path.join(root, file), "type": file_type}
                members.append(member)

        # Obtain files in mongo dict
        remote_files = self._get_mongo_files(from_path)

        # Upload members if they do not exists or have been modified
        # We will do this for performance (avoid updating unmodified files) and to avoid
        # updating a file with an older one in case there are two sources for synchronization
        # in high availability scenarios
        for member in members:
            # obtain permission
            mask = int(oct(os.stat(member["filename"]).st_mode)[-3:], 8)

            # convert to relative path
            rel_filename = os.path.relpath(member["filename"], self.path)
            # get timestamp in UTC because mongo stores upload date in UTC:
            # https://www.mongodb.com/docs/v4.0/tutorial/model-time-data/#overview
            last_modified_date = datetime.datetime.utcfromtimestamp(
                os.path.getmtime(member["filename"])
            )

            remote_file = remote_files.get(rel_filename)
            upload_date = (
                remote_file[0].uploadDate if remote_file else datetime.datetime.min
            )
            # remove processed files from dict
            remote_files.pop(rel_filename, None)

            if last_modified_date >= upload_date:
                stream = None
                fh = None
                try:
                    file_type = member["type"]
                    if file_type == "dir":
                        stream = BytesIO()
                    elif file_type == "sym":
                        stream = BytesIO(
                            os.readlink(member["filename"]).encode("utf-8")
                        )
                    else:
                        fh = open(member["filename"], "rb")
                        stream = BytesIO(fh.read())

                    metadata = {"type": file_type, "permissions": mask}

                    self.logger.debug("Sync upload {}".format(rel_filename))
                    self.fs.upload_from_stream(rel_filename, stream, metadata=metadata)

                    # delete old files
                    if remote_file:
                        for file in remote_file:
                            self.logger.debug("Sync deleting {}".format(file.filename))
                            self.fs.delete(file._id)
                finally:
                    if fh:
                        fh.close()
                    if stream:
                        stream.close()

        # delete files that are not anymore in local fs
        for remote_file in remote_files.values():
            for file in remote_file:
                self.fs.delete(file._id)

    def _get_mongo_files(self, from_path=None):
        file_dict = {}
        file_cursor = self.fs.find(no_cursor_timeout=True, sort=[("uploadDate", -1)])
        for file in file_cursor:
            if from_path and not file.filename.startswith(from_path):
                continue
            if file.filename in file_dict:
                file_dict[file.filename].append(file)
            else:
                file_dict[file.filename] = [file]
        return file_dict

    def reverse_sync(self, from_path: str):
        """
        Sync from local storage to FSMongo
        :param from_path: base directory to upload content to mongo fs
        :return: None
        """
        if os.path.isabs(from_path):
            from_path = os.path.relpath(from_path, self.path)
        self._update_mongo_fs(from_path=from_path)
