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

# Module with helper functions to manage the replacement of placeholder variables by the values of well-known enviroment variables.


# Helper function to replace placeholder variables by the content of their homonym environment variables in a record received from stdin.
export def vars [
    environment: record   # Record with environment variables to load
    defaults: record = {
        FLEET_REPOS_BASE: "/repos"
        CATALOG_REPOS_BASE: "/repos"
        PROJECT_NAME: "osm_admin"
    }  # Record with default values for the variables to be replaced
]: [
    record -> record
] {
    let in_record: record = $in

    # Environment with default values when undefined
    let full_environment: record = (
        $defaults
        | merge $environment
    )

    let variable_enumeration: string = (
        $full_environment
        | columns
        | each { |col|
            $"\${($col)}"
        }
        | str join ","
    )

    $in_record
    | to yaml
    | with-env $full_environment {
        $in
        | (
            ^envsubst $variable_enumeration
        )
    }
    | from yaml
}
