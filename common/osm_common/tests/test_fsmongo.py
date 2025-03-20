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

from io import BytesIO
import logging
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
from unittest.mock import Mock

from gridfs import GridFSBucket
from osm_common.fsbase import FsException
from osm_common.fsmongo import FsMongo
from pymongo import MongoClient
import pytest

__author__ = "Eduardo Sousa <eduardo.sousa@canonical.com>"


def valid_path():
    return tempfile.gettempdir() + "/"


def invalid_path():
    return "/#tweeter/"


@pytest.fixture(scope="function", params=[True, False])
def fs_mongo(request, monkeypatch):
    def mock_mongoclient_constructor(a, b):
        pass

    def mock_mongoclient_getitem(a, b):
        pass

    def mock_gridfs_constructor(a, b):
        pass

    monkeypatch.setattr(MongoClient, "__init__", mock_mongoclient_constructor)
    monkeypatch.setattr(MongoClient, "__getitem__", mock_mongoclient_getitem)
    monkeypatch.setattr(GridFSBucket, "__init__", mock_gridfs_constructor)
    fs = FsMongo(lock=request.param)
    fs.fs_connect({"path": valid_path(), "uri": "mongo:27017", "collection": "files"})
    return fs


def generic_fs_exception_message(message):
    return "storage exception {}".format(message)


def fs_connect_exception_message(path):
    return "storage exception Invalid configuration param at '[storage]': path '{}' does not exist".format(
        path
    )


def file_open_file_not_found_exception(storage):
    f = storage if isinstance(storage, str) else "/".join(storage)
    return "storage exception File {} does not exist".format(f)


def file_open_io_exception(storage):
    f = storage if isinstance(storage, str) else "/".join(storage)
    return "storage exception File {} cannot be opened".format(f)


def dir_ls_not_a_directory_exception(storage):
    f = storage if isinstance(storage, str) else "/".join(storage)
    return "storage exception File {} does not exist".format(f)


def dir_ls_io_exception(storage):
    f = storage if isinstance(storage, str) else "/".join(storage)
    return "storage exception File {} cannot be opened".format(f)


def file_delete_exception_message(storage):
    return "storage exception File {} does not exist".format(storage)


def test_constructor_without_logger():
    fs = FsMongo()
    assert fs.logger == logging.getLogger("fs")
    assert fs.path is None
    assert fs.client is None
    assert fs.fs is None


def test_constructor_with_logger():
    logger_name = "fs_mongo"
    fs = FsMongo(logger_name=logger_name)
    assert fs.logger == logging.getLogger(logger_name)
    assert fs.path is None
    assert fs.client is None
    assert fs.fs is None


def test_get_params(fs_mongo, monkeypatch):
    def mock_gridfs_find(self, search_query, **kwargs):
        return []

    monkeypatch.setattr(GridFSBucket, "find", mock_gridfs_find)
    params = fs_mongo.get_params()
    assert len(params) == 2
    assert "fs" in params
    assert "path" in params
    assert params["fs"] == "mongo"
    assert params["path"] == valid_path()


@pytest.mark.parametrize(
    "config, exp_logger, exp_path",
    [
        (
            {
                "logger_name": "fs_mongo",
                "path": valid_path(),
                "uri": "mongo:27017",
                "collection": "files",
            },
            "fs_mongo",
            valid_path(),
        ),
        (
            {
                "logger_name": "fs_mongo",
                "path": valid_path()[:-1],
                "uri": "mongo:27017",
                "collection": "files",
            },
            "fs_mongo",
            valid_path(),
        ),
        (
            {"path": valid_path(), "uri": "mongo:27017", "collection": "files"},
            "fs",
            valid_path(),
        ),
        (
            {"path": valid_path()[:-1], "uri": "mongo:27017", "collection": "files"},
            "fs",
            valid_path(),
        ),
    ],
)
def test_fs_connect_with_valid_config(config, exp_logger, exp_path):
    fs = FsMongo()
    fs.fs_connect(config)
    assert fs.logger == logging.getLogger(exp_logger)
    assert fs.path == exp_path
    assert type(fs.client) == MongoClient
    assert type(fs.fs) == GridFSBucket


@pytest.mark.parametrize(
    "config, exp_exception_message",
    [
        (
            {
                "logger_name": "fs_mongo",
                "path": invalid_path(),
                "uri": "mongo:27017",
                "collection": "files",
            },
            fs_connect_exception_message(invalid_path()),
        ),
        (
            {
                "logger_name": "fs_mongo",
                "path": invalid_path()[:-1],
                "uri": "mongo:27017",
                "collection": "files",
            },
            fs_connect_exception_message(invalid_path()[:-1]),
        ),
        (
            {"path": invalid_path(), "uri": "mongo:27017", "collection": "files"},
            fs_connect_exception_message(invalid_path()),
        ),
        (
            {"path": invalid_path()[:-1], "uri": "mongo:27017", "collection": "files"},
            fs_connect_exception_message(invalid_path()[:-1]),
        ),
        (
            {"path": "/", "uri": "mongo:27017", "collection": "files"},
            generic_fs_exception_message(
                "Invalid configuration param at '[storage]': path '/' is not writable"
            ),
        ),
    ],
)
def test_fs_connect_with_invalid_path(config, exp_exception_message):
    fs = FsMongo()
    with pytest.raises(FsException) as excinfo:
        fs.fs_connect(config)
    assert str(excinfo.value) == exp_exception_message


@pytest.mark.parametrize(
    "config, exp_exception_message",
    [
        (
            {"logger_name": "fs_mongo", "uri": "mongo:27017", "collection": "files"},
            'Missing parameter "path"',
        ),
        (
            {"logger_name": "fs_mongo", "path": valid_path(), "collection": "files"},
            'Missing parameters: "uri"',
        ),
        (
            {"logger_name": "fs_mongo", "path": valid_path(), "uri": "mongo:27017"},
            'Missing parameter "collection"',
        ),
    ],
)
def test_fs_connect_with_missing_parameters(config, exp_exception_message):
    fs = FsMongo()
    with pytest.raises(FsException) as excinfo:
        fs.fs_connect(config)
    assert str(excinfo.value) == generic_fs_exception_message(exp_exception_message)


@pytest.mark.parametrize(
    "config, exp_exception_message",
    [
        (
            {
                "logger_name": "fs_mongo",
                "path": valid_path(),
                "uri": "mongo:27017",
                "collection": "files",
            },
            "MongoClient crashed",
        ),
    ],
)
def test_fs_connect_with_invalid_mongoclient(
    config, exp_exception_message, monkeypatch
):
    def generate_exception(a, b=None):
        raise Exception(exp_exception_message)

    monkeypatch.setattr(MongoClient, "__init__", generate_exception)

    fs = FsMongo()
    with pytest.raises(FsException) as excinfo:
        fs.fs_connect(config)
    assert str(excinfo.value) == generic_fs_exception_message(exp_exception_message)


@pytest.mark.parametrize(
    "config, exp_exception_message",
    [
        (
            {
                "logger_name": "fs_mongo",
                "path": valid_path(),
                "uri": "mongo:27017",
                "collection": "files",
            },
            "Collection unavailable",
        ),
    ],
)
def test_fs_connect_with_invalid_mongo_collection(
    config, exp_exception_message, monkeypatch
):
    def mock_mongoclient_constructor(a, b=None):
        pass

    def generate_exception(a, b):
        raise Exception(exp_exception_message)

    monkeypatch.setattr(MongoClient, "__init__", mock_mongoclient_constructor)
    monkeypatch.setattr(MongoClient, "__getitem__", generate_exception)

    fs = FsMongo()
    with pytest.raises(FsException) as excinfo:
        fs.fs_connect(config)
    assert str(excinfo.value) == generic_fs_exception_message(exp_exception_message)


@pytest.mark.parametrize(
    "config, exp_exception_message",
    [
        (
            {
                "logger_name": "fs_mongo",
                "path": valid_path(),
                "uri": "mongo:27017",
                "collection": "files",
            },
            "GridFsBucket crashed",
        ),
    ],
)
def test_fs_connect_with_invalid_gridfsbucket(
    config, exp_exception_message, monkeypatch
):
    def mock_mongoclient_constructor(a, b=None):
        pass

    def mock_mongoclient_getitem(a, b):
        pass

    def generate_exception(a, b):
        raise Exception(exp_exception_message)

    monkeypatch.setattr(MongoClient, "__init__", mock_mongoclient_constructor)
    monkeypatch.setattr(MongoClient, "__getitem__", mock_mongoclient_getitem)
    monkeypatch.setattr(GridFSBucket, "__init__", generate_exception)

    fs = FsMongo()
    with pytest.raises(FsException) as excinfo:
        fs.fs_connect(config)
    assert str(excinfo.value) == generic_fs_exception_message(exp_exception_message)


def test_fs_disconnect(fs_mongo):
    fs_mongo.fs_disconnect()


# Example.tar.gz
# example_tar/
# ├── directory
# │   └── file
# └── symlinks
#     ├── directory_link -> ../directory/
#     └── file_link -> ../directory/file
class FakeCursor:
    def __init__(self, id, filename, metadata):
        self._id = id
        self.filename = filename
        self.metadata = metadata


class FakeFS:
    directory_metadata = {"type": "dir", "permissions": 509}
    file_metadata = {"type": "file", "permissions": 436}
    symlink_metadata = {"type": "sym", "permissions": 511}

    tar_info = {
        1: {
            "cursor": FakeCursor(1, "example_tar", directory_metadata),
            "metadata": directory_metadata,
            "stream_content": b"",
            "stream_content_bad": b"Something",
            "path": "./tmp/example_tar",
        },
        2: {
            "cursor": FakeCursor(2, "example_tar/directory", directory_metadata),
            "metadata": directory_metadata,
            "stream_content": b"",
            "stream_content_bad": b"Something",
            "path": "./tmp/example_tar/directory",
        },
        3: {
            "cursor": FakeCursor(3, "example_tar/symlinks", directory_metadata),
            "metadata": directory_metadata,
            "stream_content": b"",
            "stream_content_bad": b"Something",
            "path": "./tmp/example_tar/symlinks",
        },
        4: {
            "cursor": FakeCursor(4, "example_tar/directory/file", file_metadata),
            "metadata": file_metadata,
            "stream_content": b"Example test",
            "stream_content_bad": b"Example test2",
            "path": "./tmp/example_tar/directory/file",
        },
        5: {
            "cursor": FakeCursor(5, "example_tar/symlinks/file_link", symlink_metadata),
            "metadata": symlink_metadata,
            "stream_content": b"../directory/file",
            "stream_content_bad": b"",
            "path": "./tmp/example_tar/symlinks/file_link",
        },
        6: {
            "cursor": FakeCursor(
                6, "example_tar/symlinks/directory_link", symlink_metadata
            ),
            "metadata": symlink_metadata,
            "stream_content": b"../directory/",
            "stream_content_bad": b"",
            "path": "./tmp/example_tar/symlinks/directory_link",
        },
    }

    def upload_from_stream(self, f, stream, metadata=None):
        found = False
        for i, v in self.tar_info.items():
            if f == v["path"]:
                assert metadata["type"] == v["metadata"]["type"]
                assert stream.read() == BytesIO(v["stream_content"]).read()
                stream.seek(0)
                assert stream.read() != BytesIO(v["stream_content_bad"]).read()
                found = True
                continue
        assert found

    def find(self, type, no_cursor_timeout=True, sort=None):
        list = []
        for i, v in self.tar_info.items():
            if type["metadata.type"] == "dir":
                if v["metadata"] == self.directory_metadata:
                    list.append(v["cursor"])
            else:
                if v["metadata"] != self.directory_metadata:
                    list.append(v["cursor"])
        return list

    def download_to_stream(self, id, file_stream):
        file_stream.write(BytesIO(self.tar_info[id]["stream_content"]).read())


def test_file_extract():
    tar_path = "tmp/Example.tar.gz"
    folder_path = "tmp/example_tar"

    # Generate package
    subprocess.call(["rm", "-rf", "./tmp"])
    subprocess.call(["mkdir", "-p", "{}/directory".format(folder_path)])
    subprocess.call(["mkdir", "-p", "{}/symlinks".format(folder_path)])
    p = Path("{}/directory/file".format(folder_path))
    p.write_text("Example test")
    os.symlink("../directory/file", "{}/symlinks/file_link".format(folder_path))
    os.symlink("../directory/", "{}/symlinks/directory_link".format(folder_path))
    if os.path.exists(tar_path):
        os.remove(tar_path)
    subprocess.call(["tar", "-czvf", tar_path, folder_path])

    try:
        tar = tarfile.open(tar_path, "r")
        fs = FsMongo()
        fs.fs = FakeFS()
        fs.file_extract(compressed_object=tar, path=".")
    finally:
        os.remove(tar_path)
        subprocess.call(["rm", "-rf", "./tmp"])


def test_upload_local_fs():
    path = "./tmp/"

    subprocess.call(["rm", "-rf", path])
    try:
        fs = FsMongo()
        fs.path = path
        fs.fs = FakeFS()
        fs.sync()
        assert os.path.isdir("{}example_tar".format(path))
        assert os.path.isdir("{}example_tar/directory".format(path))
        assert os.path.isdir("{}example_tar/symlinks".format(path))
        assert os.path.isfile("{}example_tar/directory/file".format(path))
        assert os.path.islink("{}example_tar/symlinks/file_link".format(path))
        assert os.path.islink("{}example_tar/symlinks/directory_link".format(path))
    finally:
        subprocess.call(["rm", "-rf", path])


def test_upload_mongo_fs():
    path = "./tmp/"

    subprocess.call(["rm", "-rf", path])
    try:
        fs = FsMongo()
        fs.path = path
        fs.fs = Mock()
        fs.fs.find.return_value = {}

        file_content = "Test file content"

        # Create local dir and upload content to fakefs
        os.mkdir(path)
        os.mkdir("{}example_local".format(path))
        os.mkdir("{}example_local/directory".format(path))
        with open(
            "{}example_local/directory/test_file".format(path), "w+"
        ) as test_file:
            test_file.write(file_content)
        fs.reverse_sync("example_local")

        assert fs.fs.upload_from_stream.call_count == 2

        # first call to upload_from_stream, dir_name
        dir_name = "example_local/directory"
        call_args_0 = fs.fs.upload_from_stream.call_args_list[0]
        assert call_args_0[0][0] == dir_name
        assert call_args_0[1].get("metadata").get("type") == "dir"

        # second call to upload_from_stream, dir_name
        file_name = "example_local/directory/test_file"
        call_args_1 = fs.fs.upload_from_stream.call_args_list[1]
        assert call_args_1[0][0] == file_name
        assert call_args_1[1].get("metadata").get("type") == "file"

    finally:
        subprocess.call(["rm", "-rf", path])
        pass
