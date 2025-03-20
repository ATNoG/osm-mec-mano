#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright ETSI OSM Contributors
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


import os

from setuptools import setup

here = os.path.abspath(os.path.dirname(__file__))
_name = "osm_common"
README = open(os.path.join(here, "README.rst")).read()

setup(
    name=_name,
    description="OSM common utilities",
    long_description=README,
    version_command=(
        "git describe --tags --long --dirty --match v*",
        "pep440-git-full",
    ),
    author="ETSI OSM",
    author_email="osmsupport@etsi.com",
    maintainer="ETSI OSM",
    maintainer_email="osmsupport@etsi.com",
    url="https://osm.etsi.org/gitweb/?p=osm/common.git;a=summary",
    license="Apache 2.0",
    setup_requires=["setuptools-version-command"],
    packages=[_name],
    include_package_data=True,
)
