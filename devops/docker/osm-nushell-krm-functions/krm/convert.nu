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

# Module with functions to convert between the different alternative representations of a set of Kubernetes resources: folders with manifests, lists of records (concatenated manifests), or ResourceLists.


use ./concatenate.nu



# Substitute environment variables in text from stdin.
#
# Environment variables can be listed either as a string in the format accepted by the `envsubst` command (e.g. `$VAR1,$VAR2`) or as a list of strings with the environment variable names that will be formatted by the function. In case the parameter is empty, it should invoke `envsubst` with no parameters, so that it replaces all the environment variables that are found.
export def "replace environment variables" [vars_to_replace: any = ""]: [
    string -> string
] {
    # Gather reference to stdin before it is lost
    let text: string = $in

    # Adapt the input as needed
    let filter: string = (if ($vars_to_replace | describe) == "string" {
        # If it is a string, it can be used directly as filter for envsubst
        $vars_to_replace
        } else if ($vars_to_replace | describe) == "list<string>" {
        # If it is a list of strings, we can concatenate them in a single string with the right format for envsubst
        ($vars_to_replace | each {|var| $"${($var)}" } | str join ',')
    } else {
        # Handle unexpected type for $vars_to_replace
        error make {msg: $"Error: Expected a string or list of strings, but received ($vars_to_replace | describe)"}
    })

    # Proceed with the substitution
    if ($filter | is-empty) {
        $text | ^envsubst
    } else {
        $text | ^envsubst $filter
    }
}

alias replace_env_vars = replace environment variables


# Convert manifests in a source folder to a ResourceList
export def "folder to resourcelist" [
    --subst-env,   # Set if environment variables should be replaced
    folder: path,
    env_filter?: any = ""
]: [
    record -> record
    nothing -> record
] {
    # Gather the input and convert to record if empty
    let in_list: record = if $in == null { {} } else { $in }

    # Create a ResourceList from the source folder and substitute environment variables if needed
    let source_list: record = (
        kpt fn source $folder
        | if $subst_env {
            $in | replace environment variables $env_filter
        } else {
            $in
        }
        | from yaml
    )

    # Merge both resource lists carefully
    $in_list | concatenate resourcelists $source_list
}

export alias "folder to rl" = folder to resourcelist
export alias folder2list_generator = folder to resourcelist


# Convert a manifest from stdin to a ResourceList
## NOTE: It is an equivalent with type-checks to:
## kustomize cfg cat --wrap-kind ResourceList
export def "manifest to resourcelist" []: [
    any -> record
] {
    # Gather the input and convert to list
    let manifest_in: list<any> = (if $in == null { [] }
        else if ($in | describe | str starts-with "record") { [ $in ] }
        else if ($in | describe | str starts-with "list") or ($in | describe | str starts-with "table") { $in }
        else { error make {msg: $"Error: Expected a record or a list of records, but received ($in | describe)."}})

    {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: $manifest_in
    }
}

export alias manifest2list = manifest to resourcelist


# Convert a ResourceList to file manifests in a target folder
export def "resourcelist to folder" [
    --sync,                 # If sync is true, replaces all contents in the folder, otherwise just copies over.
    folder: path,
    dry_run?: bool = false  # If true, just prints the ResourceList but does not render any file
]: [
    record -> any
] {

    # Preserves the input value
    let list_in: record = $in

    # As optional parameter, defaults to $env.DRY_RUN when not set
    let is_dry_run: bool = if $dry_run == null { $env.DRY_RUN | into bool } else { $dry_run }

    # If it is a dry-run, just prints the input ResourceList and exits
    if $is_dry_run {
        return ($list_in | to yaml)
    }

    # First, render the manifests to a temporary folder
    let tmp_folder: string = (mktemp -t -d)
    let tmp_target: string = ($tmp_folder | path join manifests)
    $list_in | to yaml | ^kpt fn sink $tmp_target

    # Writes the contents to the target folder
    if $sync {
        # Sync actually removes any previous contents in the folder
        rm -rf $folder
    }
    mkdir $folder
    ls $tmp_target | get name | cp -r ...$in $folder

    # Removes the temporary folder
    rm -rf $tmp_folder
}

export alias list2folder = resourcelist to folder
