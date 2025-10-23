#!/bin/sh
#
#   Copyright 2016 Telefónica Investigación y Desarrollo, S.A.U.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

apache=0
nolicense=0
other=0
exception_list="':(exclude)*.pdf' ':(exclude)*.png' ':(exclude)*.jpeg' ':(exclude)*.jpg' ':(exclude)*.gif' ':(exclude)*.json' ':(exclude)*.ico' ':(exclude)*.svg' ':(exclude)*.tiff'"
git fetch

for file in $(echo ${exception_list} | xargs git diff --name-only origin/$GERRIT_BRANCH -- . ); do

    file_type=$(file -b --mime-type $file | sed 's|/.*||')
    echo $file is $file_type
    case "$file_type" in
        text)
            binary=false
            ;;
        *)
            binary=true
            ;;
    esac

    if $binary ; then
        license=Binary
    else
        license="No Apache license found"
        if [ -f $file ]; then
            if [ -s $file ]; then
                if [ $(grep -c "http://www.apache.org/licenses/LICENSE-2.0" $file) -ge 1 ] ; then
                    license="Apache-2.0"
                fi
            fi
        else
            license="DELETED"
        fi
    fi
    echo "$file $license"
    case "$license" in
        "Apache-2.0")
            apache=$((apache + 1))
            ;;
        No*)
            nolicense=$((nolicense + 1))
            ;;
        "DELETED")
            ;;
        "Binary")
            ;;
        *)
            echo "BAD LICENSE ON FILE $file"
            other=$((other + 1))
            ;;
    esac
done


if [ $nolicense -gt 0 ]; then
    echo "FATAL: Files without apache license found"
	exit 2
fi

exit 0
