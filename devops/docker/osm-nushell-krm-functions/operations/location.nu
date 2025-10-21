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

# Helper module to manage KSU source or target locations, so that they can be safely translated to well-known paths in the local filesystem.


# Helper function to convert a profile type name to the canonical name for that profile type so that it can build a folder path deterministically.
# NOT EXPORTED
def "normalize profile type" [
]: [
    string -> string
] {
    $in
    | if $in in ["controller", "infra-controller", "infra-controllers", "infra_controller", "infra_controllers"] {
        "infra-controller-profiles"
    } else if $in in ["config", "infra-config", "infra-configs", "infra_config", "infra_configs"] {
        "infra-config-profiles"
    } else if $in in ["managed", "resources", "managed-resources", "managed_resources"] {
        "managed-resources"
    } else if $in in ["app", "apps", "applications", "cnf", "cnfs", "nf", "nfs"] {
        "app-profiles"
    } else {
        $in
    }
}


# Helper function to convert an OKA type name to the canonical name for that OKA type so that it can build a folder path deterministically.
# NOT EXPORTED
def "normalize oka type" [
]: [
    string -> string
] {
    $in
    | if $in in ["controller", "infra-controller", "infra-controllers", "infra_controller", "infra_controllers"] {
        "infra-controllers"
    } else if $in in ["config", "infra-config", "infra-configs", "infra_config", "infra_configs"] {
        "infra-configs"
    } else if $in in ["managed", "resources", "managed-resources", "managed_resources", "cloud-resources", "cloud_resources"] {
        "cloud-resources"
    } else if $in in ["app", "apps", "applications", "cnf", "cnfs", "nf", "nfs"] {
        "apps"
    } else {
        $in
    }
}


# Convert a location into its components to determine a path in the local filesystem.
export def "to path components" [
    default_project_name: string = "osm_admin"  # Default project name
    default_repos_base: string = "/repos"  # Base path for the local repo clones
]: [
    record -> list<path>
] {
    let in_location: record = $in

    # Absolute path of the local repo clone
    let repo: string = (
        $in_location
        # Is it a path?
        | if ($in | get -i "repo-path" | is-not-empty ) {
            # $in_location
            $in
            | get "repo-path"
            | path join
        # Maybe it was specified by repo name?
        } else if (
            ($in | get -i "repo-name" | is-not-empty )
        ) {
            [
                # ($in_location | get -i "repos-base" | default $default_repos_base),
                # ($in_location | get "repo-name")
                ($in | get -i "repos-base" | default $default_repos_base),
                ($in | get "repo-name")
            ]
            | path join
        # Otherwise, throws an error
        } else {
            error make { msg: $"Error: Invalid location spec. Missing `repo-path` or `repo-name` key. Non conformant: \n($in_location | to yaml)"}
        }
        # Ensure that the absolute path starts by "/"
        | if ($in | str starts-with "/") {
            $in
        } else {
            $"/($in)"
        }
    )

    # Get the base path prior to the last item (e.g., profile path or OKA folder)
    let base: string = (
        $in_location
        # Is it a path?
        | if ($in | get -i "base-path" | is-not-empty ) {
            $in
            | get "base-path"
            | path join
        # Maybe it is a profile spec?
        } else if (
            ($in | get -i "profile-type" | is-not-empty ) and
            ($in | get -i "profile-name" | is-not-empty )
        ) {
            [
                ($in | get -i "project-name" | default $default_project_name),
                ($in | get "profile-type" | normalize profile type),
                ($in | get "profile-name")
            ]
            | path join
        # Maybe it is an OKA subfolder spec?
        } else if (
            ($in | get -i "oka-type" | is-not-empty ) and
            ($in | get -i "oka-name" | is-not-empty )
        ) {
            [
                ($in | get "oka-type" | normalize oka type),
                ($in | get "oka-name")
            ]
            | path join
        # Otherwise, it is malformed
        } else {
            error make { msg: $"Error: Invalid location spec. Missing `base-path` or `profile-type`+`profile-name` or `oka-type`+`oka-name` key. Non conformant: \n($in | to yaml)"}
        }
    )

    # Check that the final relative path is available
    if ($in_location | get -i "relative-path" | is-empty ) {
        error make { msg: $"Error: Invalid location spec. Missing `relative-path` key. Non conformant: \n($in_location | to yaml)"}
    }

    # Finally, return the path components
    [ $repo, $base, ($in_location | get "relative-path" | path join) ]
}


# Convert a location to an absolute path in the local filesystem.
export def "to absolute path" [
    default_project_name: string = "osm_admin"  # Default project name
    default_repos_base: string = "/repos"  # Base path for the local repo clones
]: [
    record -> path
] {
    $in
    | to path components $default_project_name $default_repos_base
    | path join
}


# Convert a location to a relative path in the local filesystem with respect to the root of the locally cloned repo.
export def "from base path" [
    default_project_name: string = "osm_admin"  # Default project name
]: [
    record -> path
] {
    $in
    | to path components $default_project_name
    # Drop the first item (the `repo-path`)
    | skip 1
    | path join
}
