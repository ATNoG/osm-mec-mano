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
use ../../krm/concatenate.nu *


# --- resourcelists tests ---

export def "test concatenate resourcelists empty inputs" []: [
    nothing -> nothing
] {
    let input: record = {}
    let resourcelist2: record = {}

    let actual: record = resourcelists $resourcelist2
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: []
    }

    assert equal $actual $expected
}


export def "test concatenate resourcelists empty stdin" []: [
    nothing -> nothing
] {
    let input: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2"]
    }
    let resourcelist2: record = {}

    # Simulate empty stdin by passing input as an argument
    let actual: record = resourcelists $input
    let expected: record = $input

    assert equal $actual $expected
}


export def "test concatenate resourcelists empty second list" []: [
    nothing -> nothing
] {
    let input: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2"]
    }
    let resourcelist2: record = {}

    # Simulate empty stdin by passing input as an argument
    let actual: record = resourcelists $resourcelist2
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: []
    }

    # Since we're testing with stdin, we need to simulate it
    let actual_with_stdin: record = (
        echo $input | resourcelists $resourcelist2
    )
    let expected_with_stdin: record = $input

    assert equal $actual_with_stdin $expected_with_stdin
}


export def "test concatenate resourcelists merge lists" []: [
    nothing -> nothing
] {
    let input: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2"]
    }
    let resourcelist2: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item3", "item4"]
    }

    let actual: record = (
        echo $input | resourcelists $resourcelist2
    )
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2", "item3", "item4"]
    }

    assert equal $actual $expected
}


export def "test concatenate resourcelists non-empty inputs with no items" []: [
    nothing -> nothing
] {
    let input: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
    }
    let resourcelist2: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
    }

    let actual: record = (
        echo $input | resourcelists $resourcelist2
    )
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: []
    }

    assert equal $actual $expected
}



# --- manifests tests ---

export def "test concatenate manifests empty inputs" []: [
    nothing -> nothing
] {
    let mnfst2: any = null

    let actual: list<any> = manifests $mnfst2
    let expected: list<any> = []

    assert equal $actual $expected
}


export def "test concatenate manifests empty stdin" []: [
    nothing -> nothing
] {
    let mnfst2: record = {
        name: "example"
        kind: "Deployment"
    }

    let actual: list<any> = manifests $mnfst2
    let expected: list<any> = [ $mnfst2 ]

    assert equal $actual $expected
}


export def "test concatenate manifests empty second manifest" []: [
    nothing -> nothing
] {
    let mnfst1: record = {
        name: "example1"
        kind: "Deployment"
    }

    let mnfst2: any = null

    let actual: list<any> = (
        echo $mnfst1 | manifests $mnfst2
    )
    let expected: list<any> = [ $mnfst1 ]

    assert equal $actual $expected
}


export def "test concatenate manifests single records" []: [
    nothing -> nothing
] {
    let mnfst1: record = {
        name: "example1"
        kind: "Deployment"
    }
    let mnfst2: record = {
        name: "example2"
        kind: "Service"
    }

    let actual: list<any> = (
        echo $mnfst1 | manifests $mnfst2
    )
    let expected: list<any> = [ $mnfst1, $mnfst2 ]

    assert equal $actual $expected
}


export def "test concatenate manifests lists of records" []: [
    nothing -> nothing
] {
    let mnfst1: list<any> = [
        { name: "example1", kind: "Deployment" }
        { name: "example2", kind: "Service" }
    ]
    let mnfst2: list<any> = [
        { name: "example3", kind: "Pod" }
        { name: "example4", kind: "ConfigMap" }
    ]

    let actual: list<any> = (
        echo $mnfst1 | manifests $mnfst2
    )
    let expected: list<any> = [
        { name: "example1", kind: "Deployment" }
        { name: "example2", kind: "Service" }
        { name: "example3", kind: "Pod" }
        { name: "example4", kind: "ConfigMap" }
    ]

    assert equal $actual $expected
}


export def "test concatenate manifests invalid input" []: [
    nothing -> nothing
] {
    let mnfst2: string = "Invalid manifest"

    let actual_error: error = (
        try {
            manifests $mnfst2
        } catch {
            |err| $err.msg
        }
    )

    assert equal $actual_error "Error: Expected a record or a list of records, but received string."
}
