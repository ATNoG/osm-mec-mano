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

# Module with utility functions to patch or amend Kubernetes resources (items) enumerated in a ResourceList.


# Checks that the ResourceList is an actual ResourceList
# -- NOT EXPORTED --
def "check if resourcelist" [
    name?: string
]: [
    record -> nothing
] {
    
    $in
    | if (
        $in != {}
        and (
            ($in | get -i kind) != "ResourceList"
            or ($in | get -i apiVersion) != "config.kubernetes.io/v1"
        )
    ) {
        if ($name | is-empty) {
            error make {msg: $"Error: Expected a ResourceList, but received ($in)."}
        } else {
            error make {msg: $"Error: Expected a ResourceList, but received ($in) from ($name)."}
        }
    }
}


# Keep item in ResourceList
export def "resource keep" [
    apiVersion?: string
    kind?: string,
    name?: string,
    namespace?: string,
]: [
    record -> record
] {
    let in_rl: record = $in

    # If not a valid ResourceList, throws an error; otherwise, continues
    $in_rl | check if resourcelist

    $in_rl
    | update items {|items|
        $items.items | filter {|it| (
                (($apiVersion | is-empty) or $it.apiVersion == $apiVersion)
                and (($kind | is-empty) or $it.kind == $kind)
                and (($name | is-empty) or $it.metadata.name == $name)
                and (($namespace | is-empty) or $it.metadata.namespace == $namespace)
            )
        }
    }
}


# Delete item in ResourceList
export def "resource delete" [
    apiVersion?: string
    kind?: string,
    name?: string,
    namespace?: string,
]: [
    record -> record
] {
    let in_rl: record = $in

    # If not a valid ResourceList, throws an error; otherwise, continues
    $in_rl | check if resourcelist

    $in_rl
    | update items {|items|
        $items.items | filter {|it| (
                (not ($name | is-empty) and $it.metadata.name != $name)
                or (not ($namespace | is-empty) and $it.metadata.namespace != $namespace)
                or (not ($kind | is-empty) and $it.kind != $kind)
                or (not ($apiVersion | is-empty) and $it.apiVersion != $apiVersion)
            )
        }
    }
}


# Patch item in ResourceList with a custom closure
export def "resource custom function" [
    custom_function: closure, # Custom function to apply to the keypath
    key_path: cell-path,
    value: any,
    apiVersion?: string
    kind?: string,
    name?: string,
    namespace?: string,
]: [
    record -> record
] {
    let in_rl: record = $in

    # If not a valid ResourceList, throws an error; otherwise, continues
    $in_rl | check if resourcelist

    $in_rl
    | update items {|items|
        $items.items | each {|item|
            if ((($name | is-empty) or $item.metadata.name == $name) and
                (($namespace | is-empty) or ($item | get -i metadata.namespace) == $namespace) and
                (($kind | is-empty) or ($item | get -i kind) == $kind) and
                (($apiVersion | is-empty) or ($item | get -i apiVersion) == $apiVersion)) {
                $item | do $custom_function $key_path $value
            } else {
                $item
            }
        }
    }
}


# Patch item in ResourceList with an insert. Fails if key already exists.
export def "resource insert key" [
    key_path: cell-path,
    value: any,
    apiVersion?: string
    kind?: string,
    name?: string,
    namespace?: string,
]: [
    record -> record
] {
    let in_rl: record = $in

    # If not a valid ResourceList, throws an error; otherwise, continues
    $in_rl | check if resourcelist

    $in_rl
    | (resource custom function
        { |k, v| ($in | insert $k $v) }
        $key_path
        $value
        $apiVersion
        $kind
        $name
        $namespace
    )
}


# Patch item in ResourceList with an upsert (update if exists, otherwise insert)
export def "resource upsert key" [
    key_path: cell-path,
    value: any,
    apiVersion?: string
    kind?: string,
    name?: string,
    namespace?: string,
]: [
    record -> record
] {
    let in_rl: record = $in

    # If not a valid ResourceList, throws an error; otherwise, continues
    $in_rl | check if resourcelist

    $in_rl
    | (resource custom function
        { |k, v| ($in | upsert $k $v) }
        $key_path
        $value
        $apiVersion
        $kind
        $name
        $namespace
    )
}

export alias patch_replace = resource upsert key


# Patch item in ResourceList with an update. Fails if key does not exist.
export def "resource update key" [
    key_path: cell-path,
    value: any,
    apiVersion?: string
    kind?: string,
    name?: string,
    namespace?: string,
]: [
    record -> record
] {
    let in_rl: record = $in

    # If not a valid ResourceList, throws an error; otherwise, continues
    $in_rl | check if resourcelist

    $in_rl
    | (resource custom function
        { |k, v| ($in | update $k $v) }
        $key_path
        $value
        $apiVersion
        $kind
        $name
        $namespace
    )
}


# Patch item in ResourceList by deleting a key.
export def "resource reject key" [
    key_path: cell-path,
    apiVersion?: string
    kind?: string,
    name?: string,
    namespace?: string,
]: [
    record -> record
] {
    let in_rl: record = $in

    # If not a valid ResourceList, throws an error; otherwise, continues
    $in_rl | check if resourcelist

    $in_rl
    | (resource custom function
        { |k, v| ($in | reject $k) }
        $key_path
        ""
        $apiVersion
        $kind
        $name
        $namespace
    )
}

export alias "resource delete key" = resource reject key


# Patch item in ResourceList to add a file name (and, optionally, order in the file) for an eventual conversion to a folder of manifests
export def "resource filename set" [
    --index: int, # Number of the index in the file, for multi-resource manifests
    filename: string,
    apiVersion?: string
    kind?: string,
    name?: string,
    namespace?: string,
]: [
    record -> record
] {
    let in_rl: record = $in

    # If not a valid ResourceList, throws an error; otherwise, continues
    $in_rl | check if resourcelist

    # Adds index in file if specified; otherwise, keeps the input
    let input_rl: record = if ($index | is-empty) {
        $in_rl
    } else {
        $in_rl
        | (resource upsert key
            $.metadata.annotations."config.kubernetes.io/index"
            ($index | into string)
            $apiVersion
            $kind
            $name
            $namespace
            )
        | (resource upsert key
            $.metadata.annotations."internal.config.kubernetes.io/index"
            ($index | into string)
            $apiVersion
            $kind
            $name
            $namespace
        )
    }

    # Finally, adds file name to the items in the ResourceList
    $input_rl
    | (resource upsert key
        $.metadata.annotations."config.kubernetes.io/path"
        $filename
        $apiVersion
        $kind
        $name
        $namespace
    )
    | (resource upsert key
        $.metadata.annotations."internal.config.kubernetes.io/path"
        $filename
        $apiVersion
        $kind
        $name
        $namespace
    )
}

export alias set_filename_to_items = resource filename set


# Patch item in ResourceList to append/upsert element to a list at a given key.
#
# The expected behaviour should be as follows:
#
# 1. If the key already exists, the value should be a list, and the item should be appended to the list.
# 2. If the key does not exist, the value should be created as a list with the new item.
# 3. If the key already exists but the value is not a list, it should throw an error.
#
export def "list append item" [
    key_path: cell-path,
    value: any,
    apiVersion?: string
    kind?: string,
    name?: string,
    namespace?: string,
]: [
    record -> record
] {
    let in_rl: record = $in

    # If not a valid ResourceList, throws an error; otherwise, continues
    $in_rl | check if resourcelist

    # Checks if all the preexisting values at the matching keys are lists; otherwise, throws an error
    let non_conformant: list<any> = (
        $in_rl
        # Only the resources that match the input criteria
        | (resource keep 
            $apiVersion
            $kind
            $name
            $namespace
        )
        # Only keeps the resources in a regular list
        | get -i items
        # Removes the resources where the key does not exist
        | filter { |it| ($it | get -i $key_path) != null }
        # Keeps only the resources where the key is not a list
        | filter { |it| not (
            $it
            | get -i $key_path
            | describe
            | ($in | str starts-with "list") or ($in | str starts-with "table")
            )
        }
    )

    if not ($non_conformant | is-empty) {
        error make { msg: $"Error: Some matching keys are not lists. Non conformant:\n($non_conformant | to yaml)"}
    }

    # Actual processing
    $in_rl
    | (resource custom function
        { |k, v| ($in | upsert $k {
            |row|
                let existing = ($row | get $k -i)
                if $existing == null {
                    [$v]
                } else {
                    $existing | append $value
                }
            }
          )
        }
        $key_path
        $value
        $apiVersion
        $kind
        $name
        $namespace
    )
}

export alias patch_add_to_list = list append item
export alias "list upsert item" = list append item


# Patch item in ResourceList to drop/delete element from a list at a given key with a given value.
export def "list drop item" [
    --keep-empty-list,
    key_path: cell-path,
    value: any,
    apiVersion?: string
    kind?: string,
    name?: string,
    namespace?: string,
]: [
    record -> record
] {
    let in_rl: record = $in

    # If not a valid ResourceList, throws an error; otherwise, continues
    $in_rl | check if resourcelist

    # Checks if all the preexisting values at the matching keys are lists; otherwise, throws an error
    let non_conformant: list<any> = (
        $in_rl
        # Only the resources that match the input criteria
        | (resource keep 
            $apiVersion
            $kind
            $name
            $namespace
        )
        # Only keeps the resources in a regular list
        | get -i items
        # Removes the resources where the key does not exist
        | filter { |it| ($it | get -i $key_path) != null }
        # Keeps only the resources where the key is not a list
        | filter { |it| not ($it | get -i $key_path | describe | str starts-with "list") }
    )

    if not ($non_conformant | is-empty) {
        error make { msg: $"Error: Some matching keys are not lists. Non conformant:\n($non_conformant | to yaml)"}
    }

    # Actual processing
    $in_rl
    | (resource custom function
        { |k, v| ($in
            | update $k {|row|
                $row | get $k -i | filter {|value| ($value != $v)}
            }
            # Delete the key in case the list at the key is now empty and the flag is disabled
            | if (not $keep_empty_list) and ($in | get $k -i | is-empty) {
                $in | reject $k
            } else { $in }
          )
        }
        $key_path
        $value
        $apiVersion
        $kind
        $name
        $namespace
    )
}

export alias patch_delete_from_list = list drop item
