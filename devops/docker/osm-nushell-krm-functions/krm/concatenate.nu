#######################################################################################
# Copyright ETSI Contributors and Others.
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
#######################################################################################

# Module with utility functions to concatenate descriptions of Kubernetes resources, either embedded in ResourceLists or from plain multi-resource manifests (i.e. lists of records).


# Join two ResourceLists, one from stdin and another from the first argument.
# Empty records at stdin or at the parameter are valid and should be treated as empty ResourceLists.
export def resourcelists [
    resourcelist2: record # 2nd `ResourceList` to concatenate
]: [
    record -> record
    nothing -> record
] {
    # Gather the input and convert to record if empty
    let list1: record = if $in == null { {} } else { $in }
    let list2: record = if $resourcelist2 == null { {} } else { $resourcelist2 }

    # If both are empty, returns an empty ResourceList
    if $list1 == {} and $list2 == {} {
        {
            apiVersion: "config.kubernetes.io/v1"
            kind: "ResourceList"
            items: []
        }
    } else if $list2 == {} {
        # If the second ResourceList is empty, returns just the one from stdin
        $list1
    } else {
        # Merge both resource lists strategically
        {
            apiVersion: "config.kubernetes.io/v1"
            kind: "ResourceList"
            items: ($list1.items? | append $list2.items?)
        }
        # ALTERNATIVELY: $in_list | merge deep --strategy "append" $source_list
        ## Strategy is "append", so that item lists are appended
    }
}

export alias resourcelist = resourcelists
export alias rl = resourcelists


# Join two ResourceList files
# NOT EXPORTED
def "resourcelists from files" [file1: path, file2: path] {
    let list1 = (open $file1)
    let list2 = (open $file2)
    $list1 | merge $list2
}

alias join_lists = resourcelists from files


# Join two manifests, one from stdin and another from the first argument
# Empty manifests at stdin or at the parameter are valid and should be treated as empty manifests.
export def manifests [
    mnfst2: any # 2nd manifest to concatenate
]: [
    any -> list<any>
] {

    # Gather the input and convert to list
    # let manifest1: list<any> = if $in == null { [] } else { $in }
    # let manifest2: list<any> = if $mnfst2 == null { [] } else { $mnfst2 }
    let manifest1: list<any> = (if $in == null { [] }
        else if ($in | describe | str starts-with "record") { [ $in ] }
        else if ($in | describe | str starts-with "list") or ($in | describe | str starts-with "table") { $in }
        else { error make {msg: $"Error: Expected a record or a list of records, but received ($in | describe)."}})

        let manifest2: list<any> = (if $mnfst2 == null { [] }
        else if ($mnfst2 | describe | str starts-with "record") { [ $mnfst2 ] }
        else if ($mnfst2 | describe | str starts-with "list") or ($mnfst2 | describe | str starts-with "table") { $mnfst2 }
        else { error make {msg: $"Error: Expected a record or a list of records, but received ($mnfst2 | describe)."}})

    # Return the concatenation
    [
        $manifest1
        $manifest2
    ] | flatten

    # How to convert to YAML manifests again:
    #
    # let merged_manifests = ($manifest1 | manifests $manifest2)
    # $merged_manifests
    # | each { |obj| $obj | to yaml }
    # | str join "---\n"
}

export alias manifest = manifests
