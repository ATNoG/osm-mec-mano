#!/usr/bin/env python3
# -*- coding: utf-8 -*-
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

import subprocess
import sys
import os
from setuptools import setup, find_packages
from setuptools.command.install import install


class Install_osm_im(install):
    """Generation of .py files from yang models"""
    model_dir = "models/yang"
    im_dir = "osm_im"

    def pipinstall(self, package):
        """pip install for executable dependencies"""
        subprocess.call([sys.executable, "-m", "pip", "install", package])

    def run(self):
        self.pipinstall('pyang==2.6.1')
        self.pipinstall('pyangbind==0.8.6')
        import pyangbind
        print("Using dir {}/{} for python artifacts".format(os.getcwd(), self.im_dir))
        path = "{}/{}".format(os.getcwd(), self.im_dir)

        protoc_command = ["make", "models"]
        if subprocess.call(protoc_command) != 0:
            sys.exit(-1)

        # To ensure generated files are copied to the python installation folder
        install_path = "{}{}".format(self.install_lib, self.im_dir)
        self.copy_tree(self.im_dir, install_path)
        if os.path.isfile("{}/etsi-nfv-nsd.py".format(install_path)):
            self.move_file(
                "{}/etsi-nfv-nsd.py".format(install_path), "{}/etsi_nfv_nsd.py".format(install_path)
            )
        if os.path.isfile("{}/etsi-nfv-vnfd.py".format(install_path)):
            self.move_file(
                "{}/etsi-nfv-vnfd.py".format(install_path), "{}/etsi_nfv_vnfd.py".format(install_path)
            )

        install.run(self)


setup(
    name='osm_im',
    description='OSM Information Model',
    long_description=open('README.rst').read(),
    version_command=('git describe --tags --long --dirty --match v*', 'pep440-git-full'),
    author='OSM Support',
    author_email='osmsupport@etsi.org',
    packages=find_packages(),
    include_package_data=True,
    setup_requires=['setuptools-version-command'],
    test_suite='nose.collector',
    url='https://osm.etsi.org/gitweb/?p=osm/IM.git;a=summary',
    license='Apache 2.0',
    cmdclass={'install': Install_osm_im},
)
