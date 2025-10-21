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
use ../../krm/overlaypatch.nu *



# --- add patch tests ---

export def "test overlaypatch add patch to kustomization" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let kustomization_name: string = "example-kustomization"
    let ks_namespace: string = "default"
    let target: record = {
        kind: "Deployment"
        name: "example-deployment"
    }
    let patch_value: record = {
        op: "replace"
        path: "/spec/replicas"
        value: 3
    }

    let actual: record = $resourcelist | add patch --ks-namespace $ks_namespace $kustomization_name $target $patch_value
    let expected_patch_content: record = {
        target: $target
        patch: ($patch_value | to yaml)
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


export def "test overlaypatch add patch to kustomization with existing patches" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                spec: { patches: [{ target: { kind: "Service", name: "example-service" }, patch: "op:\n  replace\npath:\n  /spec/type\nvalue:\n  NodePort" }] }
            }
        ]
    }

    let kustomization_name: string = "example-kustomization"
    let ks_namespace: string = "default"
    let target: record = {
        kind: "Deployment"
        name: "example-deployment"
    }
    let patch_value: record = {
        op: "replace"
        path: "/spec/replicas"
        value: 3
    }

    let actual: record = $resourcelist | add patch --ks-namespace $ks_namespace $kustomization_name $target $patch_value
    let expected_patch_content_1st_patch: record = {
        target: { kind: "Service", name: "example-service" }
        patch: "op:\n  replace\npath:\n  /spec/type\nvalue:\n  NodePort"
    }
    let expected_patch_content_2nd_patch: record = {
        target: $target
        patch: ($patch_value | to yaml)
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content_1st_patch, $expected_patch_content_2nd_patch] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


# --- add jsonpatch tests ---

export def "test overlaypatch add jsonpatch add operation" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let kustomization_name: string = "example-kustomization"
    let ks_namespace: string = "default"
    let target: record = {
        kind: "Deployment"
        name: "example-deployment"
    }
    let path: string = "/spec/replicas"
    let value: any = 3

    let actual: record = $resourcelist | add jsonpatch --ks-namespace $ks_namespace $kustomization_name $target $path $value
    let expected_patch_content: record = {
        target: $target
        patch: (
            [{ op: "add", path: $path, value: $value }] | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


export def "test overlaypatch add jsonpatch replace operation" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let kustomization_name: string = "example-kustomization"
    let ks_namespace: string = "default"
    let target: record = {
        kind: "Deployment"
        name: "example-deployment"
    }
    let path: string = "/spec/replicas"
    let value: any = 3

    let actual: record = $resourcelist | (
        add jsonpatch
            --ks-namespace $ks_namespace
            --operation "replace"
            $kustomization_name
            $target
            $path
            $value
    )
    let expected_patch_content: record = {
        target: $target
        patch: (
            [{ op: "replace", path: $path, value: $value }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


export def "test overlaypatch add jsonpatch remove operation" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                spec: { patches: [] }
            }
        ]
    }

    let kustomization_name: string = "example-kustomization"
    let ks_namespace: string = "default"
    let target: record = {
        kind: "Deployment"
        name: "example-deployment"
    }
    let path: string = "/spec/replicas"

    let actual: record = $resourcelist | (
        add jsonpatch
            --ks-namespace $ks_namespace
            --operation "remove"
            $kustomization_name
            $target
            $path
    )
    let expected_patch_content: record = {
        target: $target
        patch: (
            [{ op: "remove", path: $path}]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


export def "test overlaypatch add jsonpatch move operation" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let kustomization_name: string = "example-kustomization"
    let ks_namespace: string = "default"
    let target: record = {
        kind: "Deployment"
        name: "example-deployment"
    }
    let path: string = "/spec/new-replicas"
    let from: string = "/spec/replicas"

    let actual: record = (
        $resourcelist
        | add jsonpatch
            --ks-namespace $ks_namespace
            --operation "move"
            $kustomization_name
            $target
            $path
            ''
            $from
    )
    let expected_patch_content: record = {
        target: $target
        patch: (
            [{ op: "move", from: $from, path: $path }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


export def "test overlaypatch add jsonpatch copy operation" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                spec: { patches: [] }
            }
        ]
    }

    let kustomization_name: string = "example-kustomization"
    let ks_namespace: string = "default"
    let target: record = {
        kind: "Deployment"
        name: "example-deployment"
    }
    let path: string = "/spec/new-replicas"
    let from: string = "/spec/replicas"

    let actual: record = (
        $resourcelist
        | add jsonpatch
            --ks-namespace $ks_namespace
            --operation "copy"
            $kustomization_name
            $target
            $path
            ''
            $from
    )
    let expected_patch_content: record = {
        target: $target
        patch: (
            [{ op: "copy", from: $from, path: $path }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


export def "test overlaypatch add jsonpatch invalid operation" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let kustomization_name: string = "example-kustomization"
    let ks_namespace: string = "default"
    let target: record = {
        kind: "Deployment"
        name: "example-deployment"
    }
    let path: string = "/spec/replicas"

    let error_occurred: any = try {
        $resourcelist | (
            add jsonpatch
                --ks-namespace $ks_namespace
                --operation "invalid"
                $kustomization_name
                $target
                $path
        )
    } catch {
        |err| $err.msg
    }

    assert equal $error_occurred "Invalid operation type. Supported values are 'add', 'remove', 'replace', 'move', 'copy'. See RFC6902 for details"
}


# --- helmrelease add inline values tests ---

export def "test overlaypatch helmrelease add inline values with add operation" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let hr_namespace: string = ""
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let values: record = { key1: "value1", key2: "value2" }

    let actual: record = (
        $resourcelist
        | (
            helmrelease add inline values
                --ks-namespace $ks_namespace
                $kustomization_name
                $helmrelease_name
                $values
        )
    )
    let expected_patch_content: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/values", value: $values }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


export def "test overlaypatch helmrelease add inline values with replace operation" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let hr_namespace: string = ""
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let values: record = { key1: "value1", key2: "value2" }

    let actual: record = (
        $resourcelist
        | (
            helmrelease add inline values
                --ks-namespace $ks_namespace
                --operation replace
                $kustomization_name
                $helmrelease_name
                $values
        )
    )
    let expected_patch_content: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "replace", path: "/spec/values", value: $values }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


export def "test overlaypatch helmrelease add inline values with existing patches" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                spec: { patches: [
                    {
                        target: { kind: "HelmRelease", name: "existing-helmrelease" }
                        patch: (
                            [{ op: "replace", path: "/spec/values/replicaCount", value: 2 }]
                            | to yaml
                        )
                    }
                ] }
            }
        ]
    }

    let ks_namespace: string = "default"
    let hr_namespace: string = ""
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let values: record = { key1: "value1", key2: "value2" }

    let actual: record = $resourcelist | helmrelease add inline values --ks-namespace $ks_namespace $kustomization_name $helmrelease_name $values
    let expected_patch_content_new: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/values", value: $values }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [
                    {
                        target: { kind: "HelmRelease", name: "existing-helmrelease" }
                        patch: (
                            [{ op: "replace", path: "/spec/values/replicaCount", value: 2 }]
                            | to yaml
                        )
                    },
                    $expected_patch_content_new
                ] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


# --- helmrelease add values from configmap tests ---

export def "test overlaypatch helmrelease add values from configmap basic" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let hr_namespace: string = ""
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let cm_name: string = "example-configmap"
    let cm_key: string = "values.yaml"

    let actual: record = (
        $resourcelist
        | (
            helmrelease add values from configmap
                --ks-namespace $ks_namespace
                $kustomization_name
                $helmrelease_name
                $cm_name
                $cm_key
        )
    )
    let expected_patch_content: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "ConfigMap", name: $cm_name, key: $cm_key } }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


export def "test overlaypatch helmrelease add values from configmap with target path" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let hr_namespace: string = ""
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let cm_name: string = "example-configmap"
    let cm_key: string = "values.yaml"
    let target_path: string = "/custom/path"

    let actual: record = (
        $resourcelist
        | (
            helmrelease add values from configmap
                --ks-namespace $ks_namespace
                --target-path $target_path
                $kustomization_name
                $helmrelease_name
                $cm_name
                $cm_key
        )
    )
    let expected_patch_content: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "ConfigMap", name: $cm_name, key: $cm_key, targetPath: $target_path } }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


export def "test overlaypatch helmrelease add values from configmap with existing patches" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                spec: { patches: [
                    {
                        target: { kind: "HelmRelease", name: "existing-helmrelease" }
                        patch: (
                            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "ConfigMap", name: "existing-configmap", key: "existing-values.yaml" } }]
                            | to yaml
                        )
                    }
                ] }
            }
        ]
    }

    let ks_namespace: string = "default"
    let hr_namespace: string = ""
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let cm_name: string = "example-configmap"
    let cm_key: string = "values.yaml"

    let actual: record = (
        $resourcelist
        | (
            helmrelease add values from configmap
                --ks-namespace $ks_namespace
                $kustomization_name
                $helmrelease_name
                $cm_name
                $cm_key
        )
    )
    let expected_patch_content_existing: record = {
        target: { kind: "HelmRelease", name: "existing-helmrelease" }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "ConfigMap", name: "existing-configmap", key: "existing-values.yaml" } }]
            | to yaml
        )
    }
    let expected_patch_content_new: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "ConfigMap", name: $cm_name, key: $cm_key } }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content_existing, $expected_patch_content_new] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}



# --- helmrelease add values from secret tests ---

export def "test overlaypatch helmrelease add values from secret basic" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let hr_namespace: string = ""
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let secret_name: string = "example-secret"
    let secret_key: string = "values.yaml"

    let actual: record = (
        $resourcelist
        | (
            helmrelease add values from secret
                --ks-namespace $ks_namespace
                $kustomization_name
                $helmrelease_name
                $secret_name
                $secret_key
        )
    )
    let expected_patch_content: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "Secret", name: $secret_name, key: $secret_key } }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


export def "test overlaypatch helmrelease add values from secret with target path" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let hr_namespace: string = ""
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let secret_name: string = "example-secret"
    let secret_key: string = "values.yaml"
    let target_path: string = "/custom/path"

    let actual: record = (
        $resourcelist
        | (
            helmrelease add values from secret
                --ks-namespace $ks_namespace
                --target-path $target_path
                $kustomization_name
                $helmrelease_name
                $secret_name
                $secret_key
        )
    )
    let expected_patch_content: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "Secret", name: $secret_name, key: $secret_key, targetPath: $target_path } }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


export def "test overlaypatch helmrelease add values from secret with optional flag" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let hr_namespace: string = ""
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let secret_name: string = "example-secret"
    let secret_key: string = "values.yaml"

    let actual: record = (
        $resourcelist
        | (
            helmrelease add values from secret
                --ks-namespace $ks_namespace
                --optional $kustomization_name
                $helmrelease_name
                $secret_name
                $secret_key
        )
    )
    let expected_patch_content: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "Secret", name: $secret_name, key: $secret_key, optional: true } }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


export def "test overlaypatch helmrelease add values from secret with hr namespace" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let hr_namespace: string = "example-namespace"
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let secret_name: string = "example-secret"
    let secret_key: string = "values.yaml"

    let actual: record = (
        $resourcelist
        | (
            helmrelease add values from secret
                --ks-namespace $ks_namespace
                --hr-namespace $hr_namespace
                $kustomization_name
                $helmrelease_name
                $secret_name
                $secret_key
        )
    )
    let expected_patch_content: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name, namespace: $hr_namespace }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "Secret", name: $secret_name, key: $secret_key } }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


export def "test overlaypatch helmrelease add values from secret with existing patches" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                spec: { patches: [
                    {
                        target: { kind: "HelmRelease", name: "existing-helmrelease" }
                        patch: (
                            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "Secret", name: "existing-secret", key: "existing-values.yaml" } }]
                            | to yaml
                        )
                    }
                ] }
            }
        ]
    }

    let ks_namespace: string = "default"
    let hr_namespace: string = ""
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let secret_name: string = "example-secret"
    let secret_key: string = "values.yaml"

    let actual: record = (
        $resourcelist
        | (
            helmrelease add values from secret
                --ks-namespace $ks_namespace
                $kustomization_name
                $helmrelease_name
                $secret_name
                $secret_key
        )
    )
    let expected_patch_content_existing: record = {
        target: { kind: "HelmRelease", name: "existing-helmrelease" }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "Secret", name: "existing-secret", key: "existing-values.yaml" } }]
            | to yaml
        )
    }
    let expected_patch_content_new: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "Secret", name: $secret_name, key: $secret_key } }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content_existing, $expected_patch_content_new] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


# TODO:

# --- helmrelease set values ---

## Inline values only
export def "test overlaypatch helmrelease set values with inline values only" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let inline_values: record = { key1: "value1", key2: "value2" }

    let actual: record = (
        $resourcelist
        | (
            helmrelease set values
                --ks-namespace $ks_namespace
                $kustomization_name
                $helmrelease_name
                $inline_values
        )
    )
    let expected_patch_content: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/values", value: $inline_values }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


## Values from ConfigMap only
export def "test overlaypatch helmrelease set values with configmap only" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let cm_name: string = "example-configmap"

    let actual: record = (
        $resourcelist
        | (
            helmrelease set values
                --ks-namespace $ks_namespace
                $kustomization_name
                $helmrelease_name
                {}
                $cm_name
        )
    )
    let expected_patch_content: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "ConfigMap", name: $cm_name, key: "values.yaml" } }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


## Values from Secret only
export def "test overlaypatch helmrelease set values with secret only" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let secret_name: string = "example-secret"

    let actual: record = (
        $resourcelist
        | (
            helmrelease set values
                --ks-namespace $ks_namespace
                $kustomization_name
                $helmrelease_name
                {}
                ''
                $secret_name
        )
    )
    let expected_patch_content: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "Secret", name: $secret_name, key: "values.yaml" } }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


## Inline values and values from ConfigMap
export def "test overlaypatch helmrelease set values with inline and configmap" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let inline_values: record = { key1: "value1", key2: "value2" }
    let cm_name: string = "example-configmap"

    let actual: record = (
        $resourcelist
        | (
            helmrelease set values
                --ks-namespace $ks_namespace
                $kustomization_name
                $helmrelease_name
                $inline_values
                $cm_name
        )
    )
    let expected_patch_content_inline_values: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/values", value: $inline_values }]
            | to yaml
        )
    }
    let expected_patch_content_cm_values: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "ConfigMap", name: $cm_name, key: "values.yaml" } }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content_inline_values, $expected_patch_content_cm_values] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


## Inline values and values from secret
export def "test overlaypatch helmrelease set values with inline and secret" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let inline_values: record = { key1: "value1", key2: "value2" }
    let secret_name: string = "example-secret"

    let actual: record = (
        $resourcelist
        | (
            helmrelease set values
                --ks-namespace $ks_namespace
                $kustomization_name
                $helmrelease_name
                $inline_values
                ''
                $secret_name
        )
    )
    let expected_patch_content_inline_values: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/values", value: $inline_values }]
            | to yaml
        )
    }
    let expected_patch_content_secret_values: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "Secret", name: $secret_name, key: "values.yaml" } }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content_inline_values, $expected_patch_content_secret_values] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


## Values from cm and values from secret
export def "test overlaypatch helmrelease set values with configmap and secret" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let cm_name: string = "example-configmap"
    let secret_name: string = "example-secret"

    let actual: record = (
        $resourcelist
        | (
            helmrelease set values
                --ks-namespace $ks_namespace
                $kustomization_name
                $helmrelease_name
                {}
                $cm_name
                $secret_name
        )
    )
    let expected_patch_content_cm_values: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "ConfigMap", name: $cm_name, key: "values.yaml" } }]
            | to yaml
        )
    }
    let expected_patch_content_secret_values: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "Secret", name: $secret_name, key: "values.yaml" } }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content_cm_values, $expected_patch_content_secret_values] }
            }
        ]
    }

    assert equal $actual $expected_resourcelist
}


## Inline values, values from cm and values from secret
export def "test overlaypatch helmrelease set values with inline, configmap, and secret" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let inline_values: record = { key1: "value1", key2: "value2" }
    let cm_name: string = "example-configmap"
    let secret_name: string = "example-secret"

    let actual_resourcelist: record = (
        $resourcelist
        | (
            helmrelease set values
                --ks-namespace $ks_namespace 
                $kustomization_name 
                $helmrelease_name
                $inline_values 
                $cm_name 
                $secret_name 
        )
    )

    # Expected patches for inline values, ConfigMap, and Secret
    let expected_patch_inline_values: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/values", value: $inline_values }]
            | to yaml
        )
    }
    let expected_patch_cm_values: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "ConfigMap", name: $cm_name, key: "values.yaml" } }]
            | to yaml
        )
    }
    let expected_patch_secret_values: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [{ op: "add", path: "/spec/valuesFrom/-", value: { kind: "Secret", name: $secret_name, key: "values.yaml" } }]
            | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_inline_values, $expected_patch_cm_values, $expected_patch_secret_values] }
            }
        ]
    }

    assert equal $actual_resourcelist $expected_resourcelist
}


export def "test helmrelease set values with create configmap" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let cm_name: string = "example-configmap"
    let create_cm_with_values: record = { key1: "value1", key2: "value2" }

    let actual: record = (
        $resourcelist |
        (
            helmrelease set values
                --ks-namespace $ks_namespace
                --create-cm-with-values $create_cm_with_values
                $kustomization_name
                $helmrelease_name
                {}
                $cm_name
        )
    )
    let expected_cm_manifest: record = {
        apiVersion: "v1"
        kind: "ConfigMap"
        metadata: {
            name: $cm_name,
            namespace: "default"
            annotations: {
                # "config.kubernetes.io/path": "example-kustomization-example-helmrelease-example-configmap.yaml",
                # "internal.config.kubernetes.io/path": "example-kustomization-example-helmrelease-example-configmap.yaml"
                "config.kubernetes.io/path": "example-configmap.yaml",
                "internal.config.kubernetes.io/path": "example-configmap.yaml"
            }
        }
        data: {
            "values.yaml": ($create_cm_with_values | to yaml | str trim)
        }
    }
    let expected_patch_content: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [
                {
                    op: "add",
                    path: "/spec/valuesFrom/-",
                    value: { kind: "ConfigMap", name: $cm_name, key: "values.yaml" }
                }
            ] | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            },
            $expected_cm_manifest
        ]
    }

    assert equal $actual $expected_resourcelist
}


export def "test helmrelease set values with create secret" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let secret_name: string = "example-secret"
    let create_secret_with_values: record = {key1: "value1", key2: "value2"}

    let actual: record = $resourcelist | (
        helmrelease set values
            --ks-namespace $ks_namespace
            --create-secret-with-values $create_secret_with_values
            $kustomization_name
            $helmrelease_name
            {}
            ''
            $secret_name
    )
    let expected_secret_manifest: record = {
        apiVersion: "v1"
        kind: "Secret"
        metadata: {
            name: $secret_name,
            namespace: "default"
            annotations: {
                # "config.kubernetes.io/path": "example-kustomization-example-helmrelease-example-secret.yaml",
                # "internal.config.kubernetes.io/path": "example-kustomization-example-helmrelease-example-secret.yaml"
                "config.kubernetes.io/path": "example-secret.yaml",
                "internal.config.kubernetes.io/path": "example-secret.yaml"
            }
        }
        data: {
            "values.yaml": ($create_secret_with_values | to yaml | str trim | encode base64)
        }
    }
    let expected_patch_content: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [
                {
                    op: "add",
                    path: "/spec/valuesFrom/-",
                    value: { kind: "Secret", name: $secret_name, key: "values.yaml" }
                }
            ] | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            },
            $expected_secret_manifest
        ]
    }

    assert equal $actual $expected_resourcelist
}


export def "test helmrelease set values with create configmap and secret" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let cm_name: string = "example-configmap"
    let secret_name: string = "example-secret"
    let create_cm_with_values: record = { key1: "value1", key2: "value2" }
    let create_secret_with_values: record = { key3: "value3", key4: "value4" }

    let actual: record = $resourcelist | (
        helmrelease set values
            --ks-namespace $ks_namespace
            --create-cm-with-values $create_cm_with_values
            --create-secret-with-values $create_secret_with_values
            $kustomization_name
            $helmrelease_name
            {}
            $cm_name
            $secret_name
    )
    let expected_cm_manifest: record = {
        apiVersion: "v1"
        kind: "ConfigMap"
        metadata: {
            name: $cm_name,
            namespace: "default"
            annotations: {
                # "config.kubernetes.io/path": "example-kustomization-example-helmrelease-example-configmap.yaml",
                # "internal.config.kubernetes.io/path": "example-kustomization-example-helmrelease-example-configmap.yaml"
                "config.kubernetes.io/path": "example-configmap.yaml",
                "internal.config.kubernetes.io/path": "example-configmap.yaml"
            }
        }
        data: {
            "values.yaml": ($create_cm_with_values | to yaml | str trim)
        }
    }
    let expected_secret_manifest: record = {
        apiVersion: "v1"
        kind: "Secret"
        metadata: {
            name: $secret_name,
            namespace: "default",
            annotations: {
                # "config.kubernetes.io/path": "example-kustomization-example-helmrelease-example-secret.yaml",
                # "internal.config.kubernetes.io/path": "example-kustomization-example-helmrelease-example-secret.yaml"
                "config.kubernetes.io/path": "example-secret.yaml",
                "internal.config.kubernetes.io/path": "example-secret.yaml"
            }
        }
        data: {
            "values.yaml": ($create_secret_with_values | to yaml | str trim | encode base64)
        }
    }
    let expected_patch_content_cm: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [
                {
                    op: "add",
                    path: "/spec/valuesFrom/-",
                    value: { kind: "ConfigMap", name: $cm_name, key: "values.yaml" }
                }
            ] | to yaml
        )
    }
    let expected_patch_content_secret: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [
                {
                    op: "add",
                    path: "/spec/valuesFrom/-",
                    value: { kind: "Secret", name: $secret_name, key: "values.yaml" }
                }
            ] | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content_cm, $expected_patch_content_secret] }
            },
            $expected_cm_manifest,
            $expected_secret_manifest
        ]
    }

    assert equal $actual $expected_resourcelist
}


export def "test helmrelease set values with create secret and age encryption" []: [
    nothing -> nothing
] {
    let resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: "example-kustomization", namespace: "default" }
                # spec: { patches: [] }
                spec: {}
            }
        ]
    }

    let ks_namespace: string = "default"
    let kustomization_name: string = "example-kustomization"
    let helmrelease_name: string = "example-helmrelease"
    let secret_name: string = "example-secret"
    let create_secret_with_values: record = {
        key1: "value1",
        key2: "value2"
    }
    let test_public_key: string = "age1hsrtxphk7exrdc0kt8dgr8a8r3hx88v3xpsw0ezaxvefsy9asegqknppc0"
    let test_private_key: string = "AGE-SECRET-KEY-12CC3A4LEDYF4S26UV6Z2MEG7ZQL9PTU5NHH6N3FN6FLJ5HACW9LQX0UWP2"

    let actual: record = $resourcelist | (
        helmrelease set values
            --ks-namespace $ks_namespace
            --create-secret-with-values $create_secret_with_values
            --public-age-key $test_public_key
            $kustomization_name
            $helmrelease_name
            {}
            ''
            $secret_name
    )

    let expected_secret_manifest: record = {
        apiVersion: "v1"
        kind: "Secret"
        metadata: {
            name: $secret_name,
            namespace: "default"
            annotations: {
                # "config.kubernetes.io/path": "example-kustomization-example-helmrelease-example-secret.yaml",
                # "internal.config.kubernetes.io/path": "example-kustomization-example-helmrelease-example-secret.yaml"
                "config.kubernetes.io/path": "example-secret.yaml",
                "internal.config.kubernetes.io/path": "example-secret.yaml"
            }
        }
        data: {
            "values.yaml": ($create_secret_with_values | to yaml | str trim | encode base64)
        }
    }

    # NOTE: Here the secret is kept decrypted intentionally, since the same secret encrypted twice is never equal and we will need to decrypt them anyway to check they are equal
    let expected_patch_content: record = {
        target: { kind: "HelmRelease", name: $helmrelease_name }
        patch: (
            [
                {
                    op: "add",
                    path: "/spec/valuesFrom/-",
                    value: { kind: "Secret", name: $secret_name, key: "values.yaml" }
                }
            ] | to yaml
        )
    }
    let expected_resourcelist: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [
            $expected_secret_manifest,
            {
                apiVersion: "kustomize.toolkit.fluxcd.io/v1"
                kind: "Kustomization"
                metadata: { name: $kustomization_name, namespace: $ks_namespace }
                spec: { patches: [$expected_patch_content] }
            }
        ]
    }

    # Check that everything except the encrypted secret is equal
    (assert equal 
        ($actual | patch resource delete '' 'Secret')
        ($expected_resourcelist | patch resource delete '' 'Secret')
    )

    # Check that both secrets, once decrypted, are equal
    let actual_secret_manifest: record = (
        # First, extracts the manifest of the encrypted Secret
        $actual
        | patch resource keep '' 'Secret'
        | get items.0
        # Removes the filename annotations, since they are excluded from encryption
        | reject $.metadata.annotations
        # Then, decrypts the manifest using the private key
        | to yaml
        | keypair decrypt secret manifest $test_private_key
        | from yaml
    )
    (assert equal
        $actual_secret_manifest
        ($expected_secret_manifest | reject $.metadata.annotations)
    )
}
