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

# Module with custom functions to manage an App instance, invoking the corresponding KSU renderizations to appropriate target folders in a given profile.


# Import required modules
use ../krm *
# use ./replace.nu *
# use ./ksu.nu *
use ./replace.nu
use ./ksu.nu


# Create an instance of an App, based on an App instance model received from stdin.
export def create [
    --dry-run              # If set, only prints the generated ResourceList(s) along with the target folder(s) (i.e., it does not write to any folder).
    --print-target-folders # If set, print the target folder(s). Requires --dry-run.
    environment: record    # Record with environment variables to load.
]: [
    record -> nothing
    record -> table
] {
    # TODO: Format checks

    # Save the original app instance record
    let in_instance: record = $in

    # Remove from the environment those keys that are reserved, dynamic or forbidden, since they will be overriden or may cause known issues, and add one that mimics the KSU name
    const forbidden_keys: list<cell-path> = [
        $.KSU_NAME
        $.PATTERN_NAME
        $.BRICK_NAME
        # Add new reserved keys here as needed:
        # . . .
    ]
    let updated_environment: record = (
        $environment
        | reject -i ...$forbidden_keys
    )

    # Load environment variables and update the record
    let instance_rendered: record = (
        $in_instance
        | replace vars $updated_environment
    )

    # Get the key parts
    let app_name: string = ($instance_rendered | get $.metadata.name | str downcase)
    let spec: record = ($instance_rendered | get spec)
    let ksus: list<record> = ($spec | get ksus)

    # Process all App's KSUs
    $ksus | each {|k|
        $k
        | ksu create --dry-run=$dry_run --print-target-folder=$print_target_folders $updated_environment
    }
    # Make sure it only returns a value when its's not an empty list
    | if ($in | is-not-empty) { $in } else { $in | ignore }
}


# Delete an instance of an App, based on an App instance model received from stdin.
export def delete [
    --dry-run              # If set, only prints the ResourceList(s) with the resources that would be removed.
    --print-target-folders # If set, print the target folder(s) to be removed. Requires --dry-run.
    environment: record    # Record with environment variables to load.
]: [
    record -> nothing
    record -> table
] {
    # Save the original app instance record
    let in_instance: record = $in

    # Remove from the environment those keys that are reserved, dynamic or forbidden, since they will be overriden or may cause known issues, and add one that mimics the KSU name
    const forbidden_keys: list<cell-path> = [
        $.KSU_NAME
        $.PATTERN_NAME
        $.BRICK_NAME
        # Add new reserved keys here as needed:
        # . . .
    ]
    let updated_environment: record = (
        $environment
        | reject -i ...$forbidden_keys
    )

    # Load environment variables and update the record
    let instance_rendered: record = (
        $in_instance
        | replace vars $updated_environment
    )

    # Get the key parts
    let app_name: string = ($instance_rendered | get $.metadata.name | str downcase)
    let spec: record = ($instance_rendered | get spec)
    let ksus: list<record> = ($spec | get ksus)

    # Process all App's KSUs
    $ksus | each {|k|
        $k
        | ksu delete --dry-run=$dry_run --print-target-folder=$print_target_folders $updated_environment
    }
    # Make sure it only returns a value when its's not an empty list
    | if ($in | is-not-empty) { $in } else { $in | ignore }
}


# Update an instance of an App, based on an App instance model received from stdin.
export def "update existing" [
    --dry-run              # If set, only prints the ResourceList(s) with the resources that would be removed.
    --print-target-folders # If set, print the target folder(s) to be updated. Requires --dry-run.
    --diff-files           # If set, returns the list of files expected to change in the target folder(s). Requires --dry-run.
    --diffs                # If set, returns the expected full diff expected to change in the target folder(s). Requires --dry-run. It can be combined with `--diff-files`
    environment: record    # Record with environment variables to load.
]: [
    record -> nothing
    record -> table
    record -> string
] {
    # Save the original app instance record
    let in_instance: record = $in

    # Remove from the environment those keys that are reserved, dynamic or forbidden, since they will be overriden or may cause known issues, and add one that mimics the KSU name
    const forbidden_keys: list<cell-path> = [
        $.KSU_NAME
        $.PATTERN_NAME
        $.BRICK_NAME
        # Add new reserved keys here as needed:
        # . . .
    ]
    let updated_environment: record = (
        $environment
        | reject -i ...$forbidden_keys
    )

    # Load environment variables and update the record
    let instance_rendered: record = (
        $in_instance
        | replace vars $updated_environment
        # Overwrite the ksu section with its original values, since we do not want to replace the placeholders yet
        | upsert $.spec.ksus ($in_instance | get $.spec.ksus)
    )

    # Get the key parts
    let app_name: string = ($instance_rendered | get $.metadata.name | str downcase)
    let spec: record = ($instance_rendered | get spec)
    let ksus: list<record> = ($spec | get ksus)

    # Process all App's KSUs
    $ksus | each {|k|
        $k
        | (
            ksu update
                --print-target-folder=$print_target_folders
                --dry-run=$dry_run
                --diff-files=$diff_files
                --diff=$diffs
                $updated_environment
        )
    }
    # Make sure it only returns a value when it is not an empty list
    | if ($in | is-not-empty) {
        let output: any = $in
        
        # If the output is a list of strings, it better provides their concatenation
        let output_type: string = ($output | describe)
        if ($output_type == "list<string>") {
            $output | str join "\n"
        # Otherwise, it returns the value as it is
        } else {
            $output
        }
    } else { $in | ignore }
}

export alias update = update existing


# Get the Kustomizations that would be created on an instance of an App, based on an App instance model received from stdin.
export def "get kustomization" [
    environment: record    # Record with environment variables to load.
]: [
    record -> record
] {
    create --dry-run $environment
    | get $.items | default []
    | flatten
    | where apiVersion == 'kustomize.toolkit.fluxcd.io/v1'
    | where kind == 'Kustomization'
    | get $.metadata
    | select name namespace
    | default 'flux-system' namespace
}

export alias "get kustomizations" = get kustomization
export alias "get ks" = get kustomization
