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

# Module with custom functions to manage a Pattern definition, taking into account its corresponding source template and the set of transformations specified for its constituent Bricks.


use ../krm *
use ./replace.nu
use ./location.nu
use ./brick.nu

# Generate a ResourceList based on a Pattern instance model received from stdin.
#
# Initially, the ResourceList will be generated from the templates at the `source` location (replacing environment variables as needed), and then the transformations indicated by the Bricks will be applied.
export def create [
    environment: record = {}    # Record with environment variables to load
]: [
    record -> record
] {
    let in_pattern: record = $in

    # Get the pattern name and its parameters
    let pattern_name: string = ($in_pattern | get "name")
    let pattern_params: record = (
        $in_pattern
        | get -i "parameters"
        | default {}
        # If applicable, update placeholder values at the custom environment parameters
        | replace vars (
            $environment
            | upsert $.PATTERN_NAME $pattern_name
        )
    )

    # Update the environment to include the pattern name
    let updated_environment: record = (
        $environment
        | upsert $.PATTERN_NAME $pattern_name
        | merge $pattern_params
    )

    # Update the pattern record accordingly
    let updated_pattern: record = (
        $in_pattern
        | replace vars $updated_environment
    )

    # Get other key parts
    let src: string = (
        $updated_pattern
        | get "source"
        | location to absolute path
    )
    let bricks: list<record> = ($updated_pattern | get "bricks")

    # Generate ResourceList from source template folder
    let rl: record = (
        convert folder to resourcelist $src
        | replace vars $updated_environment
    )
    
    # Apply transformations according to the specified bricks
    with-env $updated_environment {
        $bricks
        | reduce --fold $rl {|elt, acc|
            $acc | brick transform $elt $updated_environment
        }
    }
}
