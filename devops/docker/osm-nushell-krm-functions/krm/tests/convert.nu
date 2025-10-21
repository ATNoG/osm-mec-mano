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
use std null-device
use ../../krm/convert.nu *


# --- replace environment variables tests ---

export def "test convert replace environment variables no vars" []: [
    nothing -> nothing
] {
    let text: string = "Hello, $USER!"

    $env.USER = "test_user"
    let actual: string = (
        echo $text | replace environment variables
    )
    let expected: string = "Hello, test_user!"

    assert equal $actual $expected
}


export def "test convert replace environment variables string vars" []: [
    nothing -> nothing
] {
    let text: string = "Hello, $USER! Your HOME is $HOME."
    let vars_to_replace: string = "$USER,$HOME"
    
    load-env {
        USER: "test_user"
        HOME: "/home/test_user"
    }

    let actual: string = (
        echo $text | replace environment variables $vars_to_replace
    )
    let expected: string = "Hello, test_user! Your HOME is /home/test_user."

    assert equal $actual $expected
}


export def "test convert replace environment variables list vars" []: [
    nothing -> nothing
] {
    let text: string = "Hello, $USER! Your HOME is $HOME."
    let vars_to_replace: list<string> = ["USER", "HOME"]

    load-env {
        USER: "test_user"
        HOME: "/home/test_user"
    }

    let actual: string = (
        echo $text | replace environment variables $vars_to_replace
    )
    let expected: string = "Hello, test_user! Your HOME is /home/test_user."

    assert equal $actual $expected
}


export def "test convert replace environment variables invalid input" []: [
    nothing -> nothing
] {
    let text: string = "Hello, $USER!"
    let vars_to_replace: int = 123

    let error_occurred: error = try {
        echo $text | replace environment variables $vars_to_replace

    } catch {
        |err| $err.msg
    }

    assert equal $error_occurred "Error: Expected a string or list of strings, but received int"
}


export def "test convert replace environment variables no replacement" []: [
    nothing -> nothing
] {
    let text: string = "Hello, $NON_EXISTENT_VAR!"
    let actual: string = (
        echo $text | replace environment variables
    )

    let expected: string = "Hello, !"

    assert equal $actual $expected
}


# --- folder to resourcelist tests ---

export def "test convert folder to resourcelist empty input" []: [
    nothing -> nothing
] {
    let folder: path = "./artifacts/empty"
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: []
    }

    let actual: record = (folder to resourcelist $folder)
    assert equal $actual $expected
}


export def "test convert folder to resourcelist no substitution" []: [
    nothing -> nothing
] {
    let folder: path = "./artifacts/jenkins/templates"
    let input_list: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2"]
    }

    let actual: record = (
        echo $input_list | folder to resourcelist $folder
    )
    let expected_items: list<string> = ["item1", "item2"] | append (
        kpt fn source $folder
        | from yaml
        | get items
    )

    assert equal $actual.apiVersion "config.kubernetes.io/v1"
    assert equal $actual.kind "ResourceList"
    assert equal $actual.items $expected_items
}


export def "test convert folder to resourcelist with substitution" []: [
    nothing -> nothing
] {
    let folder: path = "./artifacts/namespace/templates"
    let input_list: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2"]
    }
    $env.TARGET_NS = "target-namespace"

    let actual: record = (
        echo $input_list | folder to resourcelist --subst-env $folder
    )
    let expected_items: list<string> = ["item1", "item2"] | append (
        kpt fn source $folder
        | replace environment variables
        | from yaml
        | get items
    )

    assert equal $actual.apiVersion "config.kubernetes.io/v1"
    assert equal $actual.kind "ResourceList"
    assert equal $actual.items $expected_items
    assert equal $actual.items.2.metadata.name $env.TARGET_NS
}


export def "test convert folder to resourcelist with filter" []: [
    nothing -> nothing
] {
    let folder: path = "./artifacts/namespace/templates"
    let input_list: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2"]
    }
    $env.TARGET_NS = "target-namespace"
    let env_filter = "$TARGET_NS"

    let actual: record = (
        echo $input_list | folder to resourcelist --subst-env $folder $env_filter
    )
    let expected_items: list<string> = ["item1", "item2"] | append (
        kpt fn source $folder
        | replace environment variables $env_filter
        | from yaml
        | get items
    )

    assert equal $actual.apiVersion "config.kubernetes.io/v1"
    assert equal $actual.kind "ResourceList"
    assert equal $actual.items $expected_items
    assert equal $actual.items.2.metadata.name $env.TARGET_NS
}


export def "test convert folder to resourcelist invalid input" []: [
    nothing -> nothing
] {
    let folder: path = "./non-existent-folder"
    let input_list: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2"]
    }

    let error_occurred: bool = try {
        echo $input_list | folder to resourcelist $folder err> (null-device)
    } catch {
        |err| $err.msg
    }

    assert equal $error_occurred "Can't convert to record."
}



# --- manifest to resourcelist tests ---

export def "test convert manifest to resourcelist empty input" []: [
    nothing -> nothing
] {
    let actual: record = manifest to resourcelist
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: []
    }

    assert equal $actual $expected
}


export def "test convert manifest to resourcelist single record" []: [
    nothing -> nothing
] {
    let manifest: record = {
        name: "example"
        kind: "Deployment"
    }

    let actual: record = (
        $manifest | manifest to resourcelist
    )
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: [ $manifest ]
    }

    assert equal $actual $expected
}


export def "test convert manifest to resourcelist list of records" []: [
    nothing -> nothing
] {
    let manifests: list<any> = [
        { name: "example1", kind: "Deployment" }
        { name: "example2", kind: "Service" }
    ]

    let actual: record = (
        $manifests | manifest to resourcelist
    )
    let expected: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: $manifests
    }

    assert equal $actual $expected
}


export def "test convert manifest to resourcelist invalid input" []: [
    nothing -> nothing
] {
    let invalid_manifest: string = "Invalid manifest"

    let error_occurred: bool = try {
        $invalid_manifest | manifest to resourcelist
    } catch {
        |err| $err.msg
    }

    assert equal $error_occurred "Error: Expected a record or a list of records, but received string."
}



# --- resourcelist to folder tests ---

export def "test convert resourcelist to folder dry run" []: [
    nothing -> nothing
] {
    let rl: record = {
        apiVersion: "config.kubernetes.io/v1"
        kind: "ResourceList"
        items: ["item1", "item2"]
    }

    let output: record = (
        $rl | resourcelist to folder "no-folder" true | from yaml
    )

    assert equal $output $rl
}


export def "test convert resourcelist to folder no sync" []: [
    nothing -> nothing
] {
    let source_folder: path = "./artifacts/jenkins/templates/"
    let rl: record = (
        convert folder to resourcelist $source_folder
    )
    let target_folder: string = (mktemp -t -d)

    # Run the command
    $rl | resourcelist to folder $target_folder

    # Check if the contents were copied correctly
    let actual_contents: list<string> = (
        ls --short-names $target_folder
        | get name
        | sort
    )

    # Cleanup
    rm -rf $target_folder

    # Expected
    let expected_contents: list<string> = (
        ls --short-names $source_folder
        | get name
        | sort
    )

    assert equal $actual_contents $expected_contents
}


export def "test convert resourcelist to folder sync" []: [
    nothing -> nothing
] {
    let source_folder: path = "./artifacts/jenkins/templates/"
    let rl: record = (
        convert folder to resourcelist $source_folder
    )
    let target_folder: string = (mktemp -t -d)

    # Add an extra file to the target folder (it should be removed by the synchronization)
    ^touch ($target_folder | path join "extra_file.txt")

    # Run the command
    $rl | resourcelist to folder --sync $target_folder

    # Check if the contents were copied correctly
    let actual_contents: list<string> = (
        ls --short-names $target_folder
        | get name
        | sort
    )

    # Cleanup
    rm -rf $target_folder

    # Expected
    let expected_contents: list<string> = (
        ls --short-names $source_folder
        | get name
        | sort
    )

    assert equal $actual_contents $expected_contents
}


# export def "test convert resourcelist to folder invalid input" []: [
#     nothing -> nothing
# ] {
#     let invalid_input: record = { "Invalid input": "invalid value" }
#     let target_folder: string = (mktemp -t -d)

#     let error_occurred: any = try {
#         $invalid_input | resourcelist to folder $target_folder
#     } catch {
#         |err| $err.msg
#     }

#     # Cleanup
#     print $target_folder
#     # rm -rf $target_folder

#     assert equal $error_occurred "Can't convert to boolean."
# }


export def "test convert resourcelist to folder non-existent folder" []: [
    nothing -> nothing
] {
    let source_folder: path = "./artifacts/jenkins/templates/"
    let rl: record = (
        convert folder to resourcelist $source_folder
    )

    let temp_folder: string = (mktemp -t -d)
    let target_folder: string = ($temp_folder | path join "new-folder")
    mkdir $target_folder

    # Run the command
    $rl | resourcelist to folder $target_folder

    # Check if the contents were copied correctly
    let actual_contents: list<string> = (
        ls --short-names $target_folder
        | get name
        | sort
    )

    # Cleanup
    rm -rf $temp_folder

    # Expected
    let expected_contents: list<string> = (
        ls --short-names $source_folder
        | get name
        | sort
    )

    assert equal $actual_contents $expected_contents
}
