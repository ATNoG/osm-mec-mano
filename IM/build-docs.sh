#!/bin/bash
# Copyright 2018 Sandvine
# Copyright ETSI Contributors and Others.
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

PKG_DIRECTORIES="osm_im_trees models"
MDG_NAME=im
PKG_NAME=osm-${MDG_NAME}docs
DEB_INSTALL=debian/${PKG_NAME}.install
export DEBEMAIL="OSMSupport@etsi.org"
export DEBFULLNAME="ETSI OSM"

PKG_VERSION=$(git describe --match "v*" --tags --abbrev=0)
PKG_VERSION_FULL=$(git describe --match "v*" --tags --long)
PKG_VERSION_PREFIX=$(echo $PKG_VERSION | sed -e 's/v//g')
PKG_VERSION_POST=$(git rev-list $PKG_VERSION..HEAD | wc -l)

IFS='-' read -ra PKG_VERSION_FIELDS <<< "$PKG_VERSION_FULL"

if [ "$PKG_VERSION_POST" -eq 0 ]; then
    PKG_DIR="${PKG_NAME}-${PKG_VERSION_PREFIX}"
    POST_UPDATE=
else
    PKG_DIR="${PKG_NAME}-$PKG_VERSION_PREFIX.post${PKG_VERSION_POST}"
    POST_UPDATE=".post${PKG_VERSION_FIELDS[1]}"
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
sed -i -e "s/${PKG_VERSION_PREFIX}${POST_UPDATE}-1/$PKG_VERSION_PREFIX${POST_UPDATE}-${PKG_VERSION_FIELDS[2]}/g" debian/changelog
dpkg-buildpackage -uc -us -tc -rfakeroot
cd -
