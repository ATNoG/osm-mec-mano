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
binaries=0
deleted=0
exception_list="':(exclude)*.pdf' ':(exclude)*.png' ':(exclude)*.jpeg' ':(exclude)*.jpg' ':(exclude)*.gif' ':(exclude)*.json' ':(exclude)*.ico' ':(exclude)*.svg' ':(exclude)*.tiff'"
git fetch

if [ -n "${GERRIT_BRANCH}" ]; then
    COMMIT_TO_COMPARE="origin/${GERRIT_BRANCH}"
else
    COMMIT_TO_COMPARE="HEAD^"
fi

total_changes=$(git diff --name-only ${COMMIT_TO_COMPARE} -- . $(echo ${exception_list}) | wc -l)
for file in $(git diff --name-only ${COMMIT_TO_COMPARE} -- . $(echo ${exception_list})); do
    # Skip deleted files
    if [ ! -f "$file" ]; then
        deleted=$((deleted + 1))
        continue
    fi

    file_type=$(file -b --mime-type "$file" | sed 's|/.*||')
    echo "$file is $file_type"
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
        if [ -s "$file" ]; then
            if grep -q "http://www.apache.org/licenses/LICENSE-2.0" "$file"; then
                license="Apache-2.0"
            fi
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
        "Binary")
            binaries=$((binaries + 1))
            ;;
        *)
            echo "BAD LICENSE ON FILE $file"
            other=$((other + 1))
            ;;
    esac
done

echo "Changes in license in this commit: ${total_changes}"
echo "  Deleted files: ${deleted}"
echo "  Binaries: ${binaries}"
echo "  Apache license: ${apache}"
echo "  No license: ${nolicense}"
echo "  Other license: ${other}"

if [ $nolicense -gt 0 ]; then
    echo "FATAL: Files without apache license found"
	exit 2
fi

exit 0
