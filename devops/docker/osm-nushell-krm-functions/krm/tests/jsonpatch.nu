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
use ../../krm/jsonpatch.nu *


# --- create operation tests ---

export def "test jsonpatch create operation add" []: [
    nothing -> nothing
] {
    let op: string = "add"
    let path: string = "/spec/template/spec/securityContext"
    let value: record = {
        runAsUser: 10000
        fsGroup: 1337
    }

    let actual: record = create operation $op $path $value
    let expected: record = {
        op: $op,
        path: $path,
        value: $value
    }

    assert equal $actual $expected
}


export def "test jsonpatch create operation remove" []: [
    nothing -> nothing
] {
    let op: string = "remove"
    let path: string = "/spec/template/spec/securityContext"

    let actual: record = create operation $op $path
    let expected: record = {
        op: $op,
        path: $path
    }

    assert equal $actual $expected
}


export def "test jsonpatch create operation replace" []: [
    nothing -> nothing
] {
    let op: string = "replace"
    let path: string = "/spec/template/spec/securityContext"
    let value: record = {
        runAsUser: 10000
        fsGroup: 1337
    }

    let actual: record = create operation $op $path $value
    let expected: record = {
        op: $op,
        path: $path,
        value: $value
    }

    assert equal $actual $expected
}


export def "test jsonpatch create operation move" []: [
    nothing -> nothing
] {
    let op: string = "move"
    let from: string = "/spec/template/spec/securityContext"
    let path: string = "/spec/template/spec/newSecurityContext"

    let actual: record = create operation $op $path '' $from
    let expected: record = {
        op: $op,
        from: $from,
        path: $path
    }

    assert equal $actual $expected
}


export def "test jsonpatch create operation copy" []: [
    nothing -> nothing
] {
    let op: string = "copy"
    let from: string = "/spec/template/spec/securityContext"
    let path: string = "/spec/template/spec/newSecurityContext"

    let actual: record = create operation $op $path '' $from
    let expected: record = {
        op: $op,
        from: $from,
        path: $path
    }

    assert equal $actual $expected
}


export def "test jsonpatch create operation invalid op" []: [
    nothing -> nothing
] {
    let op: string = "invalid"
    let path: string = "/spec/template/spec/securityContext"

    let error_occurred: error = try {
        create operation $op $path
    } catch {
        |err| $err.msg
    }

    assert equal $error_occurred "Invalid operation type. Supported values are 'add', 'remove', 'replace', 'move', 'copy'. See RFC6902 for details."
}


export def "test jsonpatch create operation missing value for add/replace" []: [
    nothing -> nothing
] {
    let op: string = "add"
    let path: string = "/spec/template/spec/securityContext"

    let error_occurred: error = try {
        create operation $op $path
    } catch {
        |err| $err.msg
    }

    assert equal $error_occurred "Value is required for 'add' and 'replace' operations."
}


export def "test jsonpatch create operation missing from for move/copy" []: [
    nothing -> nothing
] {
    let op: string = "move"
    let path: string = "/spec/template/spec/newSecurityContext"

    let error_occurred: error = try {
        create operation $op $path
    } catch {
        |err| $err.msg
    }

    assert equal $error_occurred "Source path is required for 'move' and 'copy' operations."
}


# --- create JSON patch tests ---

export def "test jsonpatch create JSON patch basic" []: [
    nothing -> nothing
] {
    let target: record = {
        kind: "Deployment"
        name: "podinfo"
    }
    let operation: record = {
        op: "add"
        path: "/spec/template/spec/securityContext"
        value: {
            runAsUser: 10000
            fsGroup: 1337
        }
    }

    let actual: record = create $target $operation
    let expected: record = {
        target: $target,
        patch: ([$operation] | to yaml)
    }

    assert equal $actual.target $expected.target
    assert equal $actual.patch $expected.patch
}


export def "test jsonpatch create JSON patch multiple operations" []: [
    nothing -> nothing
] {
    let target: record = {
        kind: "Deployment"
        name: "podinfo"
    }
    let operation1: record = {
        op: "add"
        path: "/spec/template/spec/securityContext"
        value: {
            runAsUser: 10000
            fsGroup: 1337
        }
    }
    let operation2: record = {
        op: "replace"
        path: "/spec/replicas"
        value: 3
    }

    let actual: record = create $target $operation1 $operation2
    let expected: record = {
        target: $target,
        patch: (
            [$operation1, $operation2] | to yaml
        )
    }

    assert equal $actual.target $expected.target
    assert equal $actual.patch $expected.patch
}


export def "test jsonpatch create JSON patch using operation helper" []: [
    nothing -> nothing
] {
    let target: record = {
        kind: "Deployment"
        name: "podinfo"
    }
    let operation: record = (
        create operation add "/spec/template/spec/securityContext" {runAsUser: 10000, fsGroup: 1337}
    )

    let actual: record = create $target $operation
    let expected: record = {
        target: $target,
        patch: ([$operation] | to yaml)
    }

    assert equal $actual.target $expected.target
    assert equal $actual.patch $expected.patch
}
