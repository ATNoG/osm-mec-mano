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
use ../../krm/patch.nu *


# --- resource keep tests ---

export def "test patch resource keep no filters" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let actual: record = $resourcelist | resource keep
    let expected: record = $resourcelist

    assert equal $actual $expected
}


export def "test patch resource keep by apiVersion" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let actual: record = $resourcelist | resource keep "apps/v1"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource keep by kind" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let actual: record = $resourcelist | resource keep '' "Deployment"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource keep by name" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let actual: record = $resourcelist | resource keep '' '' "example1"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource keep by namespace" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let actual: record = $resourcelist | resource keep '' '' '' "default"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource keep multiple filters" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let actual: record = $resourcelist | resource keep "apps/v1" "Deployment" '' "default"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource keep invalid input" []: [
    nothing -> nothing
] {
    let invalid_input: record = {kind: "Invalid kind"}

    let error_occurred: any = try {
        $invalid_input | resource keep
    } catch {
        |err| $err.msg
    }

    assert ($error_occurred | str starts-with "Error: Expected a ResourceList, but received")
}



# --- resource delete tests ---

export def "test patch resource delete no filters" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let actual: record = $resourcelist | resource delete
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: []
    }

    assert equal $actual $expected
}


export def "test patch resource delete by apiVersion" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let actual: record = $resourcelist | resource delete "apps/v1"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource delete by kind" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let actual: record = $resourcelist | resource delete '' "Deployment"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource delete by name" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let actual: record = $resourcelist | resource delete '' '' "example1"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource delete by namespace" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let actual: record = $resourcelist | resource delete '' '' '' "default"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource delete multiple filters" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let actual: record = $resourcelist | resource delete "apps/v1" "Deployment" '' "default"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource delete invalid input" []: [
    nothing -> nothing
] {
    let invalid_input: record = {kind: "Invalid kind"}

    let error_occurred: any = try {
        echo $invalid_input | resource delete
    } catch {
        |err| $err.msg
    }

    assert ($error_occurred | str starts-with "Error: Expected a ResourceList, but received")

}



# --- resource custom function tests ---

export def "test patch resource custom function no filters" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let custom_function: closure = { |k: cell-path, v: any| ($in | upsert $k $v) }
    let key_path: cell-path = $.metadata.labels
    let value: any = { app: "example" }

    let actual: record = $resourcelist | resource custom function $custom_function $key_path $value
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", labels: { app: "example" } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", labels: { app: "example" } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", labels: { app: "example" } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource custom function by apiVersion" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let custom_function: closure = { |k: cell-path, v: any| ($in | upsert $k $v) }
    let key_path: cell-path = $.metadata.labels
    let value: any = { app: "example" }

    let actual: record = $resourcelist | resource custom function $custom_function $key_path $value "apps/v1"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", labels: { app: "example" } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", labels: { app: "example" } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource custom function by kind" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let custom_function: closure = { |k: cell-path, v: any| ($in | upsert $k $v) }
    let key_path: cell-path = $.metadata.labels
    let value: any = { app: "example" }

    let actual: record = $resourcelist | resource custom function $custom_function $key_path $value '' "Deployment"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", labels: { app: "example" } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", labels: { app: "example" } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource custom function by name" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let custom_function: closure = { |k: cell-path, v: any| ($in | upsert $k $v) }
    let key_path: cell-path = $.metadata.labels
    let value: any = { app: "example" }

    let actual: record = $resourcelist | resource custom function $custom_function $key_path $value '' '' "example1"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", labels: { app: "example" } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource custom function by namespace" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let custom_function: closure = { |k: cell-path, v: any| ($in | upsert $k $v) }
    let key_path: cell-path = $.metadata.labels
    let value: any = { app: "example" }

    let actual: record = $resourcelist | resource custom function $custom_function $key_path $value '' '' '' "default"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", labels: { app: "example" } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", labels: { app: "example" } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource custom function multiple filters" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let custom_function: closure = { |k: cell-path, v: any| ($in | upsert $k $v) }
    let key_path: cell-path = $.metadata.labels
    let value: any = { app: "example" }

    let actual: record = $resourcelist | resource custom function $custom_function $key_path $value "apps/v1" "Deployment" '' "default"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", labels: { app: "example" } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource custom function invalid input" []: [
    nothing -> nothing
] {
    let invalid_input: record = {kind: "Invalid kind"}

    let error_occurred: any = try {
        $invalid_input | resource custom function {|item, key_path, value| $item | update $key_path $value } $.metadata.labels { app: "example" }
    } catch {
        |err| $err.msg
    }

    assert ($error_occurred | str starts-with "Error: Expected a ResourceList, but received")
}



# --- resource upsert key tests ---

export def "test patch resource upsert key no filters" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let key_path: cell-path = $.metadata.labels
    let value: any = { app: "example" }

    let actual: record = $resourcelist | resource upsert key $key_path $value
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", labels: { app: "example" } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", labels: { app: "example" } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", labels: { app: "example" } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource upsert key by apiVersion" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let key_path: cell-path = $.metadata.labels
    let value: any = { app: "example" }

    let actual: record = $resourcelist | resource upsert key $key_path $value "apps/v1"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", labels: { app: "example" } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", labels: { app: "example" } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource upsert key by kind" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let key_path: cell-path = $.metadata.labels
    let value: any = { app: "example" }

    let actual: record = $resourcelist | resource upsert key $key_path $value '' "Deployment"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", labels: { app: "example" } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", labels: { app: "example" } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource upsert key by name" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let key_path: cell-path = $.metadata.labels
    let value: any = { app: "example" }

    let actual: record = $resourcelist | resource upsert key $key_path $value '' '' "example1"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", labels: { app: "example" } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource upsert key by namespace" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let key_path: cell-path = $.metadata.labels
    let value: any = { app: "example" }

    let actual: record = $resourcelist | resource upsert key $key_path $value '' '' '' "default"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", labels: { app: "example" } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", labels: { app: "example" } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource upsert key multiple filters" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let key_path: cell-path = $.metadata.labels
    let value: any = { app: "example" }

    let actual: record = $resourcelist | resource upsert key $key_path $value "apps/v1" "Deployment" '' "default"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", labels: { app: "example" } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource upsert key invalid input" []: [
    nothing -> nothing
] {
    let invalid_input: record = {kind: "Invalid kind"}

    let error_occurred: any = try {
        $invalid_input | resource upsert key $.metadata.labels { app: "example" }
    } catch {
        |err| $err.msg
    }

    assert ($error_occurred | str starts-with "Error: Expected a ResourceList, but received")
}



# --- resource filename set tests ---

export def "test patch resource filename set no index" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let filename: string = "example.yaml"
    let actual: record = $resourcelist | resource filename set $filename
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { "config.kubernetes.io/path": $filename, "internal.config.kubernetes.io/path": $filename } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { "config.kubernetes.io/path": $filename, "internal.config.kubernetes.io/path": $filename } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { "config.kubernetes.io/path": $filename, "internal.config.kubernetes.io/path": $filename } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource filename set with index" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let filename: string = "example.yaml"
    let index: int = 0
    let actual: record = $resourcelist | resource filename set --index $index $filename
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { "config.kubernetes.io/path": $filename, "internal.config.kubernetes.io/path": $filename, "config.kubernetes.io/index": "0", "internal.config.kubernetes.io/index": "0" } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { "config.kubernetes.io/path": $filename, "internal.config.kubernetes.io/path": $filename, "config.kubernetes.io/index": "0", "internal.config.kubernetes.io/index": "0" } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { "config.kubernetes.io/path": $filename, "internal.config.kubernetes.io/path": $filename, "config.kubernetes.io/index": "0", "internal.config.kubernetes.io/index": "0" } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource filename set by apiVersion" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let filename: string = "example.yaml"
    let actual: record = $resourcelist | resource filename set $filename "apps/v1"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { "config.kubernetes.io/path": $filename, "internal.config.kubernetes.io/path": $filename } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { "config.kubernetes.io/path": $filename, "internal.config.kubernetes.io/path": $filename } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource filename set by kind" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let filename: string = "example.yaml"
    let actual: record = $resourcelist | resource filename set $filename '' "Deployment"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { "config.kubernetes.io/path": $filename, "internal.config.kubernetes.io/path": $filename } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { "config.kubernetes.io/path": $filename, "internal.config.kubernetes.io/path": $filename } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource filename set by name" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let filename: string = "example.yaml"
    let actual: record = $resourcelist | resource filename set $filename '' '' "example1"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { "config.kubernetes.io/path": $filename, "internal.config.kubernetes.io/path": $filename } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource filename set by namespace" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let filename: string = "example.yaml"
    let actual: record = $resourcelist | resource filename set $filename '' '' '' "default"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { "config.kubernetes.io/path": $filename, "internal.config.kubernetes.io/path": $filename } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { "config.kubernetes.io/path": $filename, "internal.config.kubernetes.io/path": $filename } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch resource filename set multiple filters" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let filename: string = "example.yaml"
    let actual: record = $resourcelist | resource filename set $filename "apps/v1" "Deployment" '' "default"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { "config.kubernetes.io/path": $filename, "internal.config.kubernetes.io/path": $filename } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    assert equal $actual $expected
}



# TODO:

# --- list append item tests ---

export def "test patch list append item no filters" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let key_path: cell-path = $.metadata.annotations.example
    let value: any = "example-value"
    let actual: record = $resourcelist | list append item $key_path $value
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["example-value"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: ["example-value"] } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: ["example-value"] } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch list append item existing list" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["initial-value"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: ["initial-value"] } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: ["initial-value"] } } }
        ]
    }

    let key_path: cell-path = $.metadata.annotations.example
    let value: any = "example-value"
    let actual: record = $resourcelist | list append item $key_path $value
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["initial-value", "example-value"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: ["initial-value", "example-value"] } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: ["initial-value", "example-value"] } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch list append item existing non-list value" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: "initial-value" } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: "initial-value" } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: "initial-value" } } }
        ]
    }

    let key_path: cell-path = $.metadata.annotations.example
    let value: any = "example-value"

    let error_occurred: any = try {
        $resourcelist | list append item $key_path $value
    } catch {
        |err| $err.msg
    }

    assert ($error_occurred | str starts-with "Error: Some matching keys are not lists. Non conformant:")
}


export def "test patch list append item by apiVersion" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let key_path: cell-path = $.metadata.annotations.example
    let value: any = "example-value"
    let actual: record = $resourcelist | list append item $key_path $value "apps/v1"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["example-value"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: ["example-value"] } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch list append item by kind" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let key_path: cell-path = $.metadata.annotations.example
    let value: any = "example-value"
    let actual: record = $resourcelist | list append item $key_path $value '' "Deployment"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["example-value"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: ["example-value"] } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch list append item by name" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let key_path: cell-path = $.metadata.annotations.example
    let value: any = "example-value"
    let actual: record = $resourcelist | list append item $key_path $value '' '' "example1"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["example-value"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch list append item by namespace" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let key_path: cell-path = $.metadata.annotations.example
    let value: any = "example-value"
    let actual: record = $resourcelist | list append item $key_path $value '' '' '' "default"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["example-value"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: ["example-value"] } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch list append item multiple filters" []: [
        nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default" } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    let key_path: cell-path = $.metadata.annotations.example
    let value: any = "example-value"
    let actual: record = $resourcelist | list append item $key_path $value "apps/v1" 'Deployment' '' "default"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["example-value"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default" } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other" } }
        ]
    }

    assert equal $actual $expected
}


# TODO:

# --- list drop item tests ---

export def "test patch list drop item no filters" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["value1", "value2"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: ["value1", "value2"] } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: ["value1", "value2"] } } }
        ]
    }

    let key_path: cell-path = $.metadata.annotations.example
    let value: any = "value1"
    let actual: record = $resourcelist | list drop item $key_path $value
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["value2"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: ["value2"] } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: ["value2"] } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch list drop item existing list with multiple values" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["value1", "value2", "value3"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: ["value1", "value2", "value3"] } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: ["value1", "value2", "value3"] } } }
        ]
    }

    let key_path: cell-path = $.metadata.annotations.example
    let value: any = "value2"
    let actual: record = $resourcelist | list drop item $key_path $value
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["value1", "value3"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: ["value1", "value3"] } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: ["value1", "value3"] } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch list drop item existing non-list value" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: "value1" } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: "value1" } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: "value1" } } }
        ]
    }

    let key_path: cell-path = $.metadata.annotations.example
    let value: any = "value1"

    let error_occurred: any = try {
        $resourcelist | list drop item $key_path $value
    } catch {
        |err| $err.msg
    }

    assert ($error_occurred | str starts-with "Error: Some matching keys are not lists. Non conformant:")
}


export def "test patch list drop item by apiVersion" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["value1", "value2"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: ["value1", "value2"] } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: ["value1", "value2"] } } }
        ]
    }

    let key_path: cell-path = $.metadata.annotations.example
    let value: any = "value1"
    let actual: record = $resourcelist | list drop item $key_path $value "apps/v1"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["value2"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: ["value1", "value2"] } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: ["value2"] } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch list drop item by kind" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["value1", "value2"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: ["value1", "value2"] } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: ["value1", "value2"] } } }
        ]
    }

    let key_path: cell-path = $.metadata.annotations.example
    let value: any = "value1"
    let actual: record = $resourcelist | list drop item $key_path $value '' "Deployment"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["value2"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: ["value1", "value2"] } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: ["value2"] } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch list drop item by name" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["value1", "value2"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: ["value1", "value2"] } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: ["value1", "value2"] } } }
        ]
    }

    let key_path: cell-path = $.metadata.annotations.example
    let value: any = "value1"
    let actual: record = $resourcelist | list drop item $key_path $value '' '' "example1"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["value2"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: ["value1", "value2"] } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: ["value1", "value2"] } } }
        ]
    }

    assert equal $actual $expected
}


export def "test patch list drop item by namespace" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["value1", "value2"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: ["value1", "value2"] } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: ["value1", "value2"] } } }
        ]
    }

    let key_path: cell-path = $.metadata.annotations.example
    let value: any = "value1"
    let actual: record = $resourcelist | list drop item $key_path $value '' '' '' "default"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example1", namespace: "default", annotations: { example: ["value2"] } } }
            { apiVersion: "v1", kind: "Pod", metadata: { name: "example2", namespace: "default", annotations: { example: ["value2"] } } }
            { apiVersion: "apps/v1", kind: "Deployment", metadata: { name: "example3", namespace: "other", annotations: { example: ["value1", "value2"] } } }
        ]
    }

    assert equal $actual $expected
}
