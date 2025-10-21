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

# Module with custom functions to manage KSUs and their renderization of the corresponding ResourceList into a given target folder.


use ../krm *
use ./location.nu
use ./pattern.nu


# Render a KSU, based on a KSU instance model received from stdin.
export def create [
    --dry-run                   # If set, only prints the generated ResourceList(s) along with the target folder(s) (i.e., it does not write to any folder)
    --print-target-folder       # If set, prints the target folder. Requires --dry-run
    environment: record = {}    # Record with environment variables to load
]: [
    record -> record
    record -> nothing
] {
    # Get KSU structure
    let in_ksu: record = $in

    # Get the KSU name
    let ksu_name: string = ($in_ksu | get "name")

    # Add to the environment a key with the KSU name, so that it can be replaced
    let updated_environment: record = (
        $environment
        | upsert $.KSU_NAME $ksu_name
    )

    # Update the KSU record accordingly
    let updated_ksu: record = (
        $in_ksu
        | replace vars $updated_environment
    )

    # Get the rest of key parts
    let sync: bool = ($updated_ksu | get -i "sync" | default false)
    let target: string = (
        $updated_ksu
        | get "target"
        | location to absolute path
    )
    let patterns: list<record> = ($updated_ksu | get "patterns")

    # Process all the patterns and create a list of ResourceLists using the updated environment
    $patterns
    | each {|pat|
        $pat
        | pattern create $updated_environment
    }
    # Merge all the ResourceLists
    | reduce {|elt, acc|
        $acc
        | concatenate resourcelists $elt
    }
    # Render
    | if $dry_run {
        if $print_target_folder { print $"TARGET FOLDER: ($target)" }
        $in
    } else {
        $in
        | convert resourcelist to folder --sync=$sync $target
    }
}


# Delete a KSU, based on a KSU instance model received from stdin.
export def delete [
    --dry-run                   # If set, only prints the ResourceList(s) that would be removed (i.e., it does not write to any folder).
    --print-target-folder       # If set, prints the target folder and the list of files to be delete delete. Requires --dry-run.
    environment: record = {}    # Record with environment variables to load.
]: [
    record -> record
    record -> nothing
] {
    # Get KSU structure
    let in_ksu: record = $in

    # Get the KSU name
    let ksu_name: string = ($in_ksu | get "name")

    # Add to the environment a key with the KSU name, so that it can be replaced
    let updated_environment: record = (
        $environment
        | upsert $.KSU_NAME $ksu_name
    )

    # Update the KSU record accordingly
    let updated_ksu: record = (
        $in_ksu
        | replace vars $updated_environment
    )

    # Get the rest of key parts
    let target: string = (
        $updated_ksu
        | get "target"
        | location to absolute path
    )
    
    # Delete
    | if $dry_run {
        if $print_target_folder {
            print $"TARGET FOLDER: ($target)"
            (ls ($"($target)/**/*" | into glob ) | table -e | print)
        }
        # Returns the ResourceList that would be deleted
        {} | convert folder to resourcelist $target
    } else {
        rm -rf $target
    }
}


# Update a KSU, based on a KSU instance model received from stdin.
export def update [
    --dry-run              # If set, only prints the ResourceList(s) that would be re-generated (i.e., it does not write to any folder).
    --print-target-folder  # If set, print the target folder(s) to be updated. Requires --dry-run.
    --diff-files           # If set, lists the expected diff with respect to the existing folder(s). Requires --dry-run.
    --diff                 # If set, prints the expected diff with respect to the existing folder(s). Requires --dry-run. It can be combined with `--diff-files`.
    environment: record = {} # Record with environment variables to load.
]: [
    record -> record
    record -> string
    record -> nothing
] {
    # Get KSU structure
    let in_ksu: record = $in

    # If it is not a dry-run, we simply need to re-create the KSU and return
    if not $dry_run {
        ## Note that the raw input variables are used, since the full environment pre-processing already happens in both custom commands
        $in_ksu | delete $environment
        $in_ksu | create $environment

        return
    }
    # ... otherwise, all the dry-run calculations will need to be performed

    # Get the KSU name
    let ksu_name: string = ($in_ksu | get "name")

    # Calculate the original target folder
    let target: string = (
        $in_ksu
        | replace vars ($environment | upsert $.KSU_NAME $ksu_name)
        | get "target"
        | location to absolute path
    )

    # Generate the resource contents of the planned update in a temporary fleet repos base
    let tmp_fleet_repos_base: path = (mktemp -t -d)

    let tmp_environment: record = (
        $environment
        | upsert $.FLEET_REPOS_BASE $tmp_fleet_repos_base
    )

    let tmp_target: string = (
        $in_ksu
        | replace vars ($tmp_environment | upsert $.KSU_NAME $ksu_name)
        | get "target"
        | location to absolute path
    )

    # Render the desired manifests into a temporary location
    $in_ksu | create $tmp_environment

    # If specified, prints the target folder
    if $print_target_folder {
        print $"TARGET FOLDER: ($target)\n"
    }

    # If specified, prints all the differences with respect to the original folder
    if ($diff_files or $diff) {
        let differences: string = (
            []
            # Add list of different files, if needed
            | if $diff_files {
                $in
                | append (
                    ^diff -rqN $target $tmp_target
                    # Prevent the diff error code, due to potential file differences, ends up breaking the full pipeline
                    | complete | get stdout
                )
            # Add detail of differences, if needed
            } else { $in }
            | if $diff {
                $in
                | append (
                    ^diff -rN $target $tmp_target
                    # Prevent the diff error code, due to potential file differences, ends up breaking the full pipeline
                    | complete | get stdout
                )
            } else { $in }
            | str join "\n\n"
        )

        # Remove the temporary fleet repos base folder
        rm -rf $tmp_fleet_repos_base

        # Return the differences found by diff
        $differences

    # Otherwise, just returns the planned ResourceList
    } else {
        # Converts the planned resources to a ResourceList
        let output_rl: record = ( {} | convert folder to resourcelist $tmp_target )

        # Remove the temporary fleet repos base folder
        rm -rf $tmp_fleet_repos_base
    
        # Finally, returns the calculated ResourceList
        $output_rl
    }
}
