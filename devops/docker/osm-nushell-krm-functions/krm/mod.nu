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

# Meta-module of helper functions to manage, transform and generate specifications of Kubernetes resources.
# This meta-module comprises all the modules of the OSM's SDK for App Modelling.


# Import submodules
export module ./keypair.nu
export module ./concatenate.nu
export module ./convert.nu
export module ./generator.nu
export module ./patch.nu
export module ./jsonpatch.nu
export module ./strategicmergepatch.nu
export module ./overlaypatch.nu


# Convert input string to a safe name for Kubernetes resources
export def "safe resource name" [input: string]: [
    nothing -> string
] {
    $input
    | str downcase
    | str replace -a './' ''
    | str replace -a '.' '-'
    | str replace -a '/' '-'
    | str replace -a '_' '-'
    | str replace -a ' ' '-'
    | str replace -a ':' '-'
}

export alias safe_name = safe resource name
