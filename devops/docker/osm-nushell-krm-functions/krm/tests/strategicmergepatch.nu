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
use ../../krm/strategicmergepatch.nu *


# --- create strategic merge patch tests ---

export def "test strategicmergepatch create strategic merge patch basic" []: [
    nothing -> nothing
] {
    let target: record = {
        kind: "Deployment"
        name: "podinfo"
    }
    let patch: record = {
        apiVersion: "apps/v1"
        kind: "Deployment"
        metadata: {
            name: "not-used"
        }
        spec: {
            template: {
                metadata: {
                    annotations: {
                        "cluster-autoscaler.kubernetes.io/safe-to-evict": "true"
                    }
                }
            }
        }
    }

    let actual: record = create $target $patch
    let expected: record = {
        target: $target,
        patch: ($patch | to yaml)
    }

    assert equal $actual.target $expected.target
    assert equal $actual.patch $expected.patch
}


export def "test strategicmergepatch create strategic merge patch with dollar-patch directives" []: [
    nothing -> nothing
] {
    let target: record = {
        kind: "Deployment"
        name: "podinfo"
    }
    let patch: record = {
        apiVersion: "apps/v1"
        kind: "Deployment"
        metadata: {
            name: "not-used"
        }
        spec: {
            template: {
                metadata: {
                    annotations: {
                        "cluster-autoscaler.kubernetes.io/safe-to-evict": "true"
                    }
                }
            }
        }
        "\$patch": "replace"
    }
    
    let actual: record = create $target $patch
    let expected: record = {
        target: $target,
        patch: ($patch | to yaml)
    }

    assert equal $actual.target $expected.target
    assert equal $actual.patch $expected.patch
}


# export def "test strategicmergepatch create strategic merge patch invalid target" []: [
#     nothing -> nothing
# ] {
#     let target: record = {"Invalid target": "Invalid value"}
#     let patch: record = {
#         apiVersion: "apps/v1"
#         kind: "Deployment"
#         metadata: {
#             name: "not-used"
#         }
#         spec: {
#             template: {
#                 metadata: {
#                     annotations: {
#                         "cluster-autoscaler.kubernetes.io/safe-to-evict": "true"
#                     }
#                 }
#             }
#         }
#     }

#     let error_occurred: error = try {
#         create $target $patch
#     } catch {
#         |err| $err.msg
#     }

#     assert equal $error_occurred "Expected a record"
# }


# export def "test strategicmergepatch create strategic merge patch invalid patch" []: [
#     nothing -> nothing
# ] {
#     let target: record = {
#         kind: "Deployment"
#         name: "podinfo"
#     }
#     let patch: record = {"Invalid patch": "Invalid value"}

#     let error_occurred: error = try {
#         create $target $patch
#     } catch {
#         |err| $err.msg
#     }

#     assert equal $error_occurred "Expected a record"
# }
