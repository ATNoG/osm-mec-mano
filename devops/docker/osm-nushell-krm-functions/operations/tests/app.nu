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

# Tests of App instance management

use ../../krm *
use ../app.nu
use ../location.nu
use ../replace.nu


# --- all-in-one example (example 1) ---

export def "test app example one" []: [
    nothing -> nothing
] {
    let expected: list<record> = (
        open artifacts/sw-catalogs/apps/example1/expected_result.yaml
    )

    let fleet_repos_base: path = (mktemp -t -d)

    let environment: record = {
        FLEET_REPOS_BASE: $fleet_repos_base
        CATALOG_REPOS_BASE: ($env.pwd | path join artifacts)
        APPNAME: myapp01
        APPNAMESPACE: app-namespace
        PROFILE_TYPE: apps
        PROFILE_NAME: mycluster01
        secret-values-for-postgres-operator-myapp01: {
            POSTGRES_OPERATOR_HOST: postgres-operator-host
            POSTGRES_OPERATOR_PORT: 5432
            POSTGRES_OPERATOR_USER: postgres-operator-user
            POSTGRES_OPERATOR_PASSWORD: postgres-operator-password
        }
        secret-values-for-postgres-operator-ui-myapp01: {
            POSTGRES_OPERATOR_UI_HOST: postgres-operator-ui-host
            POSTGRES_OPERATOR_UI_PORT: 8080
            POSTGRES_OPERATOR_UI_USER: postgres-operator-ui-user
            POSTGRES_OPERATOR_UI_PASSWORD: postgres-operator-ui-password
        }
    }

    let actual: list<record> = (
        open artifacts/sw-catalogs/apps/example1/app-instance-from-model.yaml
        | app create --dry-run $environment
    )

    # Overwrites the encrypted part of the secrets in both
    let actual_trimmed: list<record> = (
        $actual
        # For each KSU's ResourceList
        | each {|k|
            $k
            # Delete sops key from all secrets
            | ( patch resource reject key $.sops '' Secret )
            # Replace encrypted value by empty string
            | ( patch resource update key $.data."values.yaml" 'ENCRYPTED' '' Secret )
        }
    )
    let expected_trimmed: list<record> = (
        $expected
        # For each KSU's ResourceList
        | each {|k|
            $k
            # Delete sops key from all secrets
            | ( patch resource reject key $.sops '' Secret )
            # Replace encrypted value by empty string
            | ( patch resource update key $.data."values.yaml" 'ENCRYPTED' '' Secret )
        }
    )

    # Checks
    assert equal $actual_trimmed $expected_trimmed

    # Cleanup
    rm -rf $fleet_repos_base
}


# --- all-in-one example (example 2) ---

export def "test app example two" []: [
    nothing -> nothing
] {
    let expected: list<record> = (
        open artifacts/sw-catalogs/apps/example2/expected_result.yaml
    )
    let fleet_repos_base: path = (mktemp -t -d)

    let environment: record = {
        FLEET_REPOS_BASE: $fleet_repos_base
        CATALOG_REPOS_BASE: ($env.pwd | path join artifacts)
        APPNAME: myapp02
        APPNAMESPACE: app-namespace
        PROFILE_TYPE: apps
        PROFILE_NAME: mycluster02
        secret-values-for-postgres-operator-myapp02: {
            POSTGRES_OPERATOR_HOST: postgres-operator-host
            POSTGRES_OPERATOR_PORT: 5432
            POSTGRES_OPERATOR_USER: postgres-operator-user
            POSTGRES_OPERATOR_PASSWORD: postgres-operator-password
        }
        secret-values-for-postgres-operator-ui-myapp01: {
            POSTGRES_OPERATOR_UI_HOST: postgres-operator-ui-host
            POSTGRES_OPERATOR_UI_PORT: 8080
            POSTGRES_OPERATOR_UI_USER: postgres-operator-ui-user
            POSTGRES_OPERATOR_UI_PASSWORD: postgres-operator-ui-password
        }
    }

    let actual: list<record> = (
        open artifacts/sw-catalogs/apps/example2/app-instance-from-model.yaml
        | app create --dry-run $environment
    )

    # Overwrites the encrypted part of the secrets in both
    let actual_trimmed: list<record> = (
        $actual
        # For each KSU's ResourceList
        | each {|k|
            $k
            # Delete sops key from all secrets
            | ( patch resource reject key $.sops '' Secret )
            # Replace encrypted value by empty string
            | ( patch resource update key $.data."values.yaml" 'ENCRYPTED' '' Secret )
        }
    )
    let expected_trimmed: list<record> = (
        $expected
        # For each KSU's ResourceList
        | each {|k|
            $k
            # Delete sops key from all secrets
            # | ( patch resource reject key $.sops '' Secret )
            # Replace encrypted value by empty string
            # | ( patch resource update key $.data."values.yaml" 'ENCRYPTED' '' Secret )
        }
    )

    # Checks
    assert equal $actual_trimmed $expected_trimmed

    # Cleanup
    rm -rf $fleet_repos_base
}


export def "test app example two written to folder" []: [
    nothing -> nothing
] {
    let expected: list<record> = (
        open artifacts/sw-catalogs/apps/example2/expected_result.yaml
    )
    let fleet_repos_base: path = (mktemp -t -d)

    let environment: record = {
        FLEET_REPOS_BASE: $fleet_repos_base
        CATALOG_REPOS_BASE: ($env.pwd | path join artifacts)
        APPNAME: myapp02
        APPNAMESPACE: app-namespace
        PROFILE_TYPE: apps
        PROFILE_NAME: mycluster02
        secret-values-for-postgres-operator-myapp02: {
            POSTGRES_OPERATOR_HOST: postgres-operator-host
            POSTGRES_OPERATOR_PORT: 5432
            POSTGRES_OPERATOR_USER: postgres-operator-user
            POSTGRES_OPERATOR_PASSWORD: postgres-operator-password
        }
        secret-values-for-postgres-operator-ui-myapp01: {
            POSTGRES_OPERATOR_UI_HOST: postgres-operator-ui-host
            POSTGRES_OPERATOR_UI_PORT: 8080
            POSTGRES_OPERATOR_UI_USER: postgres-operator-ui-user
            POSTGRES_OPERATOR_UI_PASSWORD: postgres-operator-ui-password
        }
    }

    # Retrieve instance model
    let instance_model: record = (open artifacts/sw-catalogs/apps/example2/app-instance-from-model.yaml)

    # Write to folder
    $instance_model | app create $environment

    # Calculate the actual ResourceLists from the target folders
    let targets: list<string> = (
        $instance_model
        | replace vars $environment
        | get $.spec.ksus
        | each {|k|
            $k
            | get "target"
            | location to absolute path
        }
    )
    let actual: list<record> = (
        $targets
        | each {|t|
            {} | convert folder to resourcelist $t
        }
    )

    # Overwrites the encrypted part of the secrets in both
    let actual_trimmed: list<record> = (
        $actual
        # For each KSU's ResourceList
        | each {|k|
            $k
            # Delete sops key from all secrets
            | ( patch resource reject key $.sops '' Secret )
            # Replace encrypted value by empty string
            | ( patch resource update key $.data."values.yaml" 'ENCRYPTED' '' Secret )
        }
    )
    let expected_trimmed: list<record> = (
        $expected
        # For each KSU's ResourceList
        | each {|k|
            $k
            # Delete sops key from all secrets
            # | ( patch resource reject key $.sops '' Secret )
            # Replace encrypted value by empty string
            # | ( patch resource update key $.data."values.yaml" 'ENCRYPTED' '' Secret )
        }
    )

    # Ensures that the items from both ResourceLists are sorted in the same order and removes irrelevant indexes and keys from `kpt`
    let actual_fixed: list<record> = ($actual_trimmed | get $.items.0 | sort-by $.kind | sort-by $.metadata.name
    | each {|k|
        $k
        | reject -i $.metadata.annotations."config.kubernetes.io/index"
        | reject -i $.metadata.annotations."internal.config.kubernetes.io/index"
        | reject -i $.metadata.annotations."internal.config.kubernetes.io/seqindent"
    })
    let expected_fixed = ($expected_trimmed | get $.items.0 | sort-by $.kind | sort-by $.metadata.name
    | each {|k|
        $k
        | reject -i $.metadata.annotations."config.kubernetes.io/index"
        | reject -i $.metadata.annotations."internal.config.kubernetes.io/index"
        | reject -i $.metadata.annotations."internal.config.kubernetes.io/seqindent"
    })

    # Checks
    assert equal $actual_fixed $expected_fixed

    # Cleanup
    rm -rf $fleet_repos_base
}
