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

# Module with KRM generator functions for various kinds of Kubernetes resources.


use ./convert.nu
use ./concatenate.nu
use ./patch.nu
use ./keypair.nu


# KRM generator function with input from a ResourceList.
# Works as generic generator function to insert any resource from a ResourceList, passed as parameter, into another ResourceList, passed from stdin.
export def "from resourcelist" [
    rl: record
]: [
    record -> record
] {
    # Regularizes ResourceList from stdin
    let list1: record = if $in == null { {} } else { $in }

    # Regularizes the second ResourceList
    let list2: record = if $rl == null { {} } else { $rl }

    # Checks that both ResourceLists are actual ResourceLists
    {stdin: $list1, "input parameter": $list2} | items { |name, rl|
        if (
            $rl != {}
            and (
                ($rl | get -i kind) != "ResourceList"
                or ($rl | get -i apiVersion) != "config.kubernetes.io/v1"
            )
        ) {
            error make {msg: $"Error: Expected a ResourceList, but received ($rl) from ($name)."}
        }
    }

    # Merges both ResourceLists
    $list1
    | concatenate resourcelists $list2
}


# KRM generator function with input from a manifest
#
# Example of use: Generator from an encrypted secret:
#
# use ./keypair.nu
#
# let secret_value: string = "my_secret_value"
# let secret_name: string = "mysecret"
# let secret_key: string = "mykey"
# let public_key: string = "age1s236gmpr7myjjyqfrl6hwz0npqjgxa9t6tjj46yq28j2c4nk653saqreav"
#
# {}
# | generator from manifest (
#     $secret_value
#     | (^kubectl create secret generic ($secret_name)
#         --from-file=($secret_key)=/dev/stdin
#         --dry-run=client
#         -o yaml)
#     | keypair encrypt_secret_from_stdin $public_key
#     | from yaml
# )
# | to yaml
#
# RESULT:
#
# apiVersion: config.kubernetes.io/v1
# kind: ResourceList
# items:
# - apiVersion: v1
#   data:
#     mykey: ENC[AES256_GCM,data:XKTW8X5ZI6c3yWYtyOPUP/UskKc=,iv:ZOkqLmSgXNCNCQrsMUq7iDL05rklDBuTaVS6E5Bgyl8=,tag:/2rLYqnh+RJWWH4OmEHJBA==,type:str]
#   kind: Secret
#   metadata:
#     creationTimestamp: null
#     name: mysecret
#   sops:
#     kms: []
#     gcp_kms: []
#     azure_kv: []
#     hc_vault: []
#     age:
#     - recipient: age1s236gmpr7myjjyqfrl6hwz0npqjgxa9t6tjj46yq28j2c4nk653saqreav
#       enc: |
#         -----BEGIN AGE ENCRYPTED FILE-----
#         YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSByNk9KWnhBa2xiMFpyT1Fj
#         QWw3aGxRZnhHbUNOcXUvc05zZDZIckdPWWtNCm91VzUwU2l5NnVSajJyQkhBMldK
#         ZkJYWXFTd1J5Q2Z1cTJ6MExkeVBWVXcKLS0tIHpKQ0EvdmpzNS9nZFFHK0JoV0Rx
#         NXRyMXROK2p3bkpnOXowQ1RYdFk2blkKzsJiw31EA7hZbcRaHe0RkjsrSs7GQjXc
#         YNAtoPquu0xaocX3pEUV/aojG/WejNY7peDXVDI43yfv8eJlO072Sw==
#         -----END AGE ENCRYPTED FILE-----
#     lastmodified: 2025-03-10T17:47:08Z
#     mac: ENC[AES256_GCM,data:JZttY7AvtRmVaJpCIdJc4Tve7EykKpR7SETQoR7fSiFOVfm4EX+ZcwYoxQYiMsNWXnx/K/IAo8VKoT1+x/lsyFTFucP3YsZ35cfXtAPt43d+gi+IEYS9hfjDQL4BmLAlIiwmij0QGOzcWFFSDhatD717zIBzEDbs2qNGHTqc68E=,iv:Dtiwbvb7LPTyShw2DrnpM/EAWdLyxSDimh7Kk15Jox4=,tag:1VBGnQbotN5KDSmznvNPdg==,type:str]
#     pgp: []
#     encrypted_regex: ^(data|stringData)$
#     version: 3.8.1
export def "from manifest" [
    manifest: any
]: [
    record -> record
    nothing -> record
] {
    # Keeps prior ResourceList, with regularization if needed
    let in_rl: record = if $in == null { {} } else { $in }

    # Regularizes the manifest in the parameter so that is is a list
    let manifest1: list<any> = (if $manifest == null { [] }
        else if ($manifest | describe | str starts-with "record") { [ $manifest ] }
        else if ($manifest | describe | str starts-with "list") or ($manifest | describe | str starts-with "table") { $manifest }
        else { error make {msg: $"Error: Expected a record or a list of records, but received ($manifest | describe)."}})

    # Creates a ResourceList from the manifest and merges with ResourceList from stdin
    $in_rl
    | concatenate resourcelists ($manifest1 | convert manifest to resourcelist)
}


# KRM generator function for a ConfigMap
export def "configmap" [
    --filename: string, # File name to keep the manifest
    --index: int,       # Number of the index in the file, for multi-resource manifests
    key_pairs: record,  # Key-value pairs to add to the ConfigMap
    name: string,
    namespace?: string = "default"
]: [
    record -> record
    nothing -> record
] {
    # Regularizes ResourceList from stdin
    let in_rl: record = if $in == null { {} } else { $in }

    $in_rl
    | ( from manifest
        # ConfigMap manifest structure 
        {
            apiVersion: v1,
            kind: ConfigMap,
            metadata: {
                name: $name,
                namespace: $namespace,
            },
            data: $key_pairs
        }
    )
    # Add file name if required
    | if ($filename | is-empty) {
        $in
    } else {
        $in
        | (patch resource filename set
            --index $index
            $filename
            "v1"
            "ConfigMap"
            $name
            $namespace
        )
    }
}


# KRM generator function for a Secret
export def "secret" [
    --filename: string, # File name to keep the manifest
    --index: int,       # Number of the index in the file, for multi-resource manifests
    --public-age-key: string # Age key to encrypt the contents of the Secret manifest
    --type: string      # Type of Kubernetes secret. Built-in types: `Opaque` (default), `kubernetes.io/service-account-token`, `kubernetes.io/dockercfg`, `kubernetes.io/dockerconfigjson`, `kubernetes.io/basic-auth`, `kubernetes.io/ssh-auth`, `kubernetes.io/tls`, `bootstrap.kubernetes.io/token`
    key_pairs: record,  # Key-value pairs to add to the Secret
    name: string,
    namespace?: string = "default"
]: [
    record -> record
    nothing -> record
] {
    # Regularizes ResourceList from stdin
    let in_rl: record = if $in == null { {} } else { $in }

    # Encode the values with base64
    let encoded_key_pairs: record = (
        ($key_pairs | columns)
        | zip (
            $key_pairs
            | values
            | each {$in | encode base64}
        )
        | reduce -f {} {|it, acc| $acc | upsert $it.0 $it.1 }
    )

    # Generate the secret
    $in_rl
    | ( from manifest
        # ConfigMap manifest structure 
        (
            {
                apiVersion: v1,
                kind: Secret,
                metadata: {
                    name: $name,
                    namespace: $namespace,
                },
                data: $encoded_key_pairs
            }
            # Add Secret type if specified
            | if ($type | is-empty) {
                $in
            } else {
                $in
                | insert type $type
            }
            # Encode if an age key was supplied
            | if ($public_age_key | is-empty) {
                $in
            } else {
                $in
                | to yaml
                | keypair encrypt_secret_from_stdin $public_age_key
                | from yaml
            }
        )
    )
    # Add file name if required
    | if ($filename | is-empty) {
        $in
    } else {
        $in
        | (patch resource filename set
            --index $index
            $filename
            "v1"
            "Secret"
            $name
            $namespace
        )
    }
}
