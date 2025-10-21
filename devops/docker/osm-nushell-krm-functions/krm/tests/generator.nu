#!/usr/bin/env -S nu --stdin
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


use std assert
use ../../krm/generator.nu *


# --- from resourcelist tests ---

export def "test generator from resourcelist empty inputs" []: [
    nothing -> nothing
] {
    let in_rl: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2"]
    }
    let rl: record = {}

    let actual: record = ($in_rl | from resourcelist $rl)
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2"]
    }

    assert equal $actual $expected
}


export def "test generator from resourcelist empty stdin" []: [
    nothing -> nothing
] {
    let in_rl: record = {}
    let rl: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2"]
    }

    let actual: record = ($in_rl | from resourcelist $rl)
    let expected: record = $rl

    assert equal $actual $expected
}


export def "test generator from resourcelist merge lists" []: [
    nothing -> nothing
] {
    let in_rl: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2"]
    }
    let rl: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item3", "item4"]
    }

    let actual: record = (
        echo $in_rl | from resourcelist $rl
    )
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2", "item3", "item4"]
    }

    assert equal $actual $expected
}


export def "test generator from resourcelist non-empty inputs with no items" []: [
    nothing -> nothing
] {
    let in_rl: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
    }
    let rl: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
    }

    let actual: record = (
        echo $in_rl | from resourcelist $rl
    )
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: []
    }

    assert equal $actual $expected
}


export def "test generator from resourcelist invalid input parameter" []: [
    nothing -> nothing
] {
    let in_rl: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2"]
    }
    let rl: record = { "Invalid input": "Invalid value" }

    let error_occurred: any = try {
        $in_rl | from resourcelist $rl
    } catch {
        |err| $err.json | from json | get inner.msg.0
    }

    assert ($error_occurred | str starts-with "Error: Expected a ResourceList, but received")
}


export def "test generator from resourcelist invalid input from stdin" []: [
    nothing -> nothing
] {
    let in_rl: record = { "Invalid input": "Invalid value" }
    let rl: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2"]
    }

    let error_occurred: any = try {
        $in_rl | from resourcelist $rl
    } catch {
        |err| $err.json | from json | get inner.msg.0
    }

    assert ($error_occurred | str starts-with "Error: Expected a ResourceList, but received")
}


# --- from manifest tests ---

export def "test generator from manifest empty inputs" []: [
    nothing -> nothing
] {
    let manifest: any = null

    let actual: record = from manifest $manifest
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: []
    }

    assert equal $actual $expected
}


export def "test generator from manifest empty stdin" []: [
    nothing -> nothing
] {
    let manifest: record = {
        name: "example"
        kind: "Deployment"
    }

    let actual: record = from manifest $manifest
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [ $manifest ]
    }

    assert equal $actual $expected
}


export def "test generator from manifest merge lists" []: [
    nothing -> nothing
] {
    let in_rl: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2"]
    }
    let manifest: record = {
        name: "example"
        kind: "Deployment"
    }

    let actual: record = (
        echo $in_rl | from manifest $manifest
    )
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2", $manifest]
    }

    assert equal $actual.apiVersion $expected.apiVersion
    assert equal $actual.kind $expected.kind
    assert equal $actual.items $expected.items
}


export def "test generator from manifest list of manifests" []: [
    nothing -> nothing
] {
    let in_rl: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2"]
    }
    let manifest: list<any> = [
        { name: "example1", kind: "Deployment" }
        { name: "example2", kind: "Service" }
    ]

    let actual: record = (
        echo $in_rl | from manifest $manifest
    )
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2", { name: "example1", kind: "Deployment" }, { name: "example2", kind: "Service" }]
    }

    assert equal $actual.apiVersion $expected.apiVersion
    assert equal $actual.kind $expected.kind
    assert equal $actual.items $expected.items
}


export def "test generator from manifest invalid input" []: [
    nothing -> nothing
] {
    let manifest: string = "Invalid manifest"

    let error_occurred: error = try {
        from manifest $manifest
    } catch {
        |err| $err.msg
    }

    assert equal $error_occurred "Error: Expected a record or a list of records, but received string."
}



# --- configmap tests ---

export def "test generator configmap basic" []: [
    nothing -> nothing
] {
    let key_pairs: record = {
        key1: "value1",
        key2: "value2"
    }
    let name: string = "example-configmap"

    let actual: record = configmap $key_pairs $name
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1",
        kind: ResourceList,
        items: [
            {
                apiVersion: "v1"
                kind: "ConfigMap"
                metadata: { name: $name, namespace: "default" }
                data: $key_pairs
            }
        ]
    }

    assert equal $actual $expected
}


export def "test generator configmap with namespace" []: [
    nothing -> nothing
] {
    let key_pairs: record = {
        key1: "value1",
        key2: "value2"
    }
    let name: string = "example-configmap"
    let namespace: string = "custom-namespace"

    let actual: record = configmap $key_pairs $name $namespace
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1",
        kind: ResourceList,
        items: [
            {
                apiVersion: "v1"
                kind: "ConfigMap"
                metadata: { name: $name, namespace: $namespace }
                data: $key_pairs
            }
        ]
    }

    assert equal $actual $expected
}


export def "test generator configmap with filename" []: [
    nothing -> nothing
] {
    let key_pairs: record = {
        key1: "value1",
        key2: "value2"
    }
    let name: string = "example-configmap"
    let filename: string = "example-configmap.yaml"

    let actual: record = configmap --filename $filename $key_pairs $name
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1",
        kind: ResourceList,
        items: [
            {
                apiVersion: "v1"
                kind: "ConfigMap"
                metadata: {
                    name: $name,
                    namespace: "default",
                    annotations: {
                        "config.kubernetes.io/path": $filename,
                        "internal.config.kubernetes.io/path": $filename
                    }
                }
                data: $key_pairs
            }
        ]
    }

    assert equal $actual $expected
}


export def "test generator configmap with filename and index" []: [
    nothing -> nothing
] {
    let key_pairs: record = {
        key1: "value1",
        key2: "value2"
    }
    let name: string = "example-configmap"
    let filename: string = "example-configmap.yaml"
    let index: int = 0

    let actual: record = configmap --filename $filename --index $index $key_pairs $name
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1",
        kind: ResourceList,
        items: [
            {
                apiVersion: "v1"
                kind: "ConfigMap"
                metadata: {
                    name: $name,
                    namespace: "default",
                    annotations: {
                        "config.kubernetes.io/path": $filename,
                        "internal.config.kubernetes.io/path": $filename,
                        "config.kubernetes.io/index": "0",
                        "internal.config.kubernetes.io/index": "0"
                    }
                }
                data: $key_pairs
            }
        ]
    }

    assert equal $actual $expected
}



# TODO:

# --- secret tests ---

export def "test generator secret basic" []: [
    nothing -> nothing
] {
    let key_pairs: record = {
        key1: "value1",
        key2: "value2"
    }
    let name: string = "example-secret"

    let actual: record = secret $key_pairs $name
    let expected_encoded_values: record = {
        key1: ("value1" | encode base64),
        key2: ("value2" | encode base64)
    }
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1",
        kind: ResourceList,
        items: [
            {
                apiVersion: "v1"
                kind: "Secret"
                metadata: { name: $name, namespace: "default" }
                data: $expected_encoded_values
            }
        ]
    }

    assert equal $actual $expected
}


export def "test generator secret with namespace" []: [
    nothing -> nothing
] {
    let key_pairs: record = {
        key1: "value1",
        key2: "value2"
    }
    let name: string = "example-secret"
    let namespace: string = "custom-namespace"

    let actual: record = secret $key_pairs $name $namespace
    let expected_encoded_values: record = {
        key1: ("value1" | encode base64),
        key2: ("value2" | encode base64)
    }
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1",
        kind: ResourceList,
        items: [
            {
                apiVersion: "v1"
                kind: "Secret"
                metadata: { name: $name, namespace: $namespace }
                data: $expected_encoded_values
            }
        ]
    }

    assert equal $actual $expected
}


export def "test generator secret with filename" []: [
    nothing -> nothing
] {
    let key_pairs: record = {
        key1: "value1",
        key2: "value2"
    }
    let name: string = "example-secret"
    let filename: string = "example-secret.yaml"

    let actual: record = (
        secret
            --filename $filename
            $key_pairs
            $name
    )
    let expected_encoded_values: record = {
        key1: ("value1" | encode base64),
        key2: ("value2" | encode base64)
    }
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1",
        kind: ResourceList,
        items: [
            {
                apiVersion: "v1"
                kind: "Secret"
                metadata: {
                    name: $name,
                    namespace: "default",
                    annotations: {
                        "config.kubernetes.io/path": $filename,
                        "internal.config.kubernetes.io/path": $filename
                    }
                }
                data: $expected_encoded_values
            }
        ]
    }

    assert equal $actual $expected
}


export def "test generator secret with filename and index" []: [
    nothing -> nothing
] {
    let key_pairs: record = {
        key1: "value1",
        key2: "value2"
    }
    let name: string = "example-secret"
    let filename: string = "example-secret.yaml"
    let index: int = 0

    let actual: record = (
        secret
            --filename $filename
            --index $index
            $key_pairs
            $name
    )
    let expected_encoded_values: record = {
        key1: ("value1" | encode base64),
        key2: ("value2" | encode base64)
    }
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1",
        kind: ResourceList,
        items: [
            {
                apiVersion: "v1"
                kind: "Secret"
                metadata: {
                    name: $name,
                    namespace: "default",
                    annotations: {
                        "config.kubernetes.io/path": $filename,
                        "internal.config.kubernetes.io/path": $filename,
                        "config.kubernetes.io/index": "0",
                        "internal.config.kubernetes.io/index": "0"
                    }
                }
                data: $expected_encoded_values
            }
        ]
    }

    assert equal $actual $expected
}


export def "test generator secret with type" []: [
    nothing -> nothing
] {
    let key_pairs: record = {
        key1: "value1",
        key2: "value2"
    }
    let name: string = "example-secret"
    let type: string = "Opaque"

    let actual: record = secret --type $type $key_pairs $name
    let expected_encoded_values: record = {
        key1: ("value1" | encode base64),
        key2: ("value2" | encode base64)
    }
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1",
        kind: ResourceList,
        items: [
            {
                apiVersion: "v1"
                kind: "Secret"
                metadata: { name: $name, namespace: "default" }
                type: $type
                data: $expected_encoded_values
            }
        ]
    }

    assert equal $actual $expected
}


export def "test generator secret with age encryption" []: [
    nothing -> nothing
] {
    let test_public_key: string = "age1hsrtxphk7exrdc0kt8dgr8a8r3hx88v3xpsw0ezaxvefsy9asegqknppc0"
    let test_private_key: string = "AGE-SECRET-KEY-12CC3A4LEDYF4S26UV6Z2MEG7ZQL9PTU5NHH6N3FN6FLJ5HACW9LQX0UWP2"

    let key_pairs: record = {
        key1: "value1",
        key2: "value2"
    }
    let name: string = "example-secret"
    let filename: string = "example-secret.yaml"

    # Here we extract the encrypted manifest only
    # File name and index are also removed, since they were not taken into account for age encryptio
    let result: record = (
        secret
            --filename $filename
            --public-age-key $test_public_key
            $key_pairs
            $name
    )
    | get items.0
    | reject $.metadata.annotations

    # Verify decryption
    let tmp_encrypted_file = (mktemp -t --suffix .yaml)
    $result | save -f $tmp_encrypted_file
    let actual: record = (
        $test_private_key
        | SOPS_AGE_KEY_FILE="/dev/stdin" sops --decrypt $tmp_encrypted_file
        | from yaml
    )
    rm $tmp_encrypted_file  # Clean up temporary key file


    let expected_encoded_values: record = {
        key1: ("value1" | encode base64),
        key2: ("value2" | encode base64)
    }

    let expected: record = {
        apiVersion: "v1"
        kind: "Secret"
        metadata: {
            name: $name,
            namespace: "default"
        }
        data: $expected_encoded_values
    }

    assert equal $actual $expected
}
