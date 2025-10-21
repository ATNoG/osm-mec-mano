#!/bin/sh
#
# Copyright ETSI
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

# Download helm chart dependencies
helm dependency update installers/helm/osm

PKG_DIRECTORIES="library jenkins installers tools docker"
MDG_NAME=devops
DEB_INSTALL=debian/osm-$MDG_NAME.install
export DEBEMAIL="OSM_TECH@LIST.ETSI.ORG"
export DEBFULLNAME="Open Source MANO"

PKG_VERSION=$(git describe --match "v*" --tags --abbrev=0)
PKG_VERSION_PREFIX=$(echo $PKG_VERSION | sed -e 's/v//g')
PKG_VERSION_POST=$(git rev-list $PKG_VERSION..HEAD | wc -l)
if [ "$PKG_VERSION_POST" -eq 0 ]; then
    PKG_DIR="osm-${MDG_NAME}-${PKG_VERSION_PREFIX}"
else
    PKG_DIR="osm-${MDG_NAME}-$PKG_VERSION_PREFIX.post${PKG_VERSION_POST}"
fi

rm -rf $PKG_DIR
rm -f *.orig.tar.xz
rm -f *.deb
rm -f $DEB_INSTALL
mkdir -p $PKG_DIR

for dir in $PKG_DIRECTORIES; do
    ln -s $PWD/$dir $PKG_DIR/.
    echo "$dir/* usr/share/osm-$MDG_NAME/$dir" >> $DEB_INSTALL
done
cp LICENSE $PKG_DIR/.
echo "LICENSE usr/share/osm-$MDG_NAME" >> $DEB_INSTALL
cp -R debian $PKG_DIR/.

cd $PKG_DIR
dh_make -y --indep --createorig --a -c apache
dpkg-buildpackage -uc -us -tc -rfakeroot
cd -

