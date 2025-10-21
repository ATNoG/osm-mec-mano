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
use ../../krm/keypair.nu *


# --- create age tests ---

export def "test keypair create age basic functionality" [] {
    # Setup
    let test_dir = (mktemp -t -d)
    let key_name = "test_key"

    # Execute
    create age $key_name $test_dir err> (null-device)

    # Assert
    assert ([$test_dir $"($key_name).key"] | path join | path exists)
    assert ([$test_dir $"($key_name).pub"] | path join | path exists)

    # Cleanup
    rm -rf $test_dir
}


export def "test keypair create age overwrites existing keys" [] {
    # Setup
    let test_dir = (mktemp -t -d)
    let key_name = "test_key"
    touch ([$test_dir $"($key_name).key"] | path join)
    touch ([$test_dir $"($key_name).pub"] | path join)

    # Execute
    create age $key_name $test_dir err> (null-device)

    # Assert
    let key_path = [$test_dir $"($key_name).key"] | path join
    let pub_path = [$test_dir $"($key_name).pub"] | path join
    assert ($key_path | path exists)
    assert ($pub_path | path exists)
    assert greater (open $key_path | str length) 0
    assert greater (open $pub_path | str length) 0

    # Cleanup
    rm -rf $test_dir
}


export def "test keypair create age uses default directory" [] {
    # Setup
    let original_credentials_dir = $env.CREDENTIALS_DIR?
    let test_dir = (mktemp -t -d)
    $env.CREDENTIALS_DIR = $test_dir
    let key_name = "test_key"

    # Execute
    create age $key_name err> (null-device)

    # Assert
    assert ([$test_dir $"($key_name).key"] | path join | path exists)
    assert ([$test_dir $"($key_name).pub"] | path join | path exists)

    # Cleanup
    rm -rf $test_dir
    $env.CREDENTIALS_DIR = $original_credentials_dir
}


export def "test keypair create age generates valid keys" [] {
    # Setup
    let test_dir = (mktemp -t -d)
    let key_name = "test_key"

    # Execute
    create age $key_name $test_dir err> (null-device)

    # Assert
    let pub_path = [$test_dir $"($key_name).pub"] | path join
    let pub_key = (open $pub_path)
    assert ($pub_key | str starts-with "age1")
    assert equal ($pub_key | str length) 63  # Standard length for age public keys

    # Cleanup
    rm -rf $test_dir
}


# --- encrypt secret manifest tests ---

export def "test keypair encrypt secret manifest basic functionality" [] {
    # Setup
    let test_public_key: string = "age1hsrtxphk7exrdc0kt8dgr8a8r3hx88v3xpsw0ezaxvefsy9asegqknppc0"
    let test_private_key: string = "AGE-SECRET-KEY-12CC3A4LEDYF4S26UV6Z2MEG7ZQL9PTU5NHH6N3FN6FLJ5HACW9LQX0UWP2"
    let input_yaml: string = "apiVersion: v1\nkind: Secret\nmetadata:\n  name: test-secret\ndata:\n  username: dXNlcm5hbWU=\n  password: cGFzc3dvcmQ="

    # Execute
    let result = ($input_yaml | encrypt secret manifest $test_public_key)

    # Assert
    assert ($result | str contains "sops:")
    assert ($result | str contains "encrypted_regex: ^(data|stringData)$")
    assert ($result | str contains "ENC[AES256_GCM,data:")

    # Verify decryption
    let tmp_encrypted_file = (mktemp -t --suffix .yaml)
    $result | save -f $tmp_encrypted_file

    let decrypted: string = ($test_private_key
        | SOPS_AGE_KEY_FILE="/dev/stdin" sops --decrypt $tmp_encrypted_file
    )
    rm $tmp_encrypted_file  # Clean up temporary key file

    assert str contains $decrypted "username: dXNlcm5hbWU="
    assert str contains $decrypted "password: cGFzc3dvcmQ="
}


export def "test keypair encrypt secret manifest handles empty input" [] {
    # Setup
    let test_public_key = "age1hsrtxphk7exrdc0kt8dgr8a8r3hx88v3xpsw0ezaxvefsy9asegqknppc0"

    # Execute and Assert
    let result: string = (try { ""
    | encrypt secret manifest $test_public_key
    } catch { $in | to yaml })

    # assert str contains $result "Error"
    assert (not ($result | str contains "Error")) $"ERROR: Got ($result)"
}


export def "test keypair encrypt secret manifest encrypts correct fields" [] {
    # Setup
    let test_public_key: string = "age1hsrtxphk7exrdc0kt8dgr8a8r3hx88v3xpsw0ezaxvefsy9asegqknppc0"
    let test_private_key: string = "AGE-SECRET-KEY-12CC3A4LEDYF4S26UV6Z2MEG7ZQL9PTU5NHH6N3FN6FLJ5HACW9LQX0UWP2"
    let input_yaml: string = "apiVersion: v1\nkind: Secret\nmetadata:\n  name: test-secret\ndata:\n  username: dXNlcm5hbWU=\n  password: cGFzc3dvcmQ=\nstringData:\n  api_key: my-api-key"

    # Execute
    let result: string = ($input_yaml | encrypt secret manifest $test_public_key)

    # Assert
    assert str contains $result "ENC[AES256_GCM,data:"
    assert str contains $result "username:"
    assert str contains $result "password:"
    assert str contains $result "api_key:"
    assert (not ($result | str contains "dXNlcm5hbWU="))
    assert (not ($result | str contains "cGFzc3dvcmQ="))
    assert (not ($result | str contains "my-api-key"))
    assert str contains $result "metadata:\n  name: test-secret"

    # Verify decryption
    let tmp_encrypted_file = (mktemp -t --suffix .yaml)
    $result | save -f $tmp_encrypted_file
    let decrypted: string = ($test_private_key
        | SOPS_AGE_KEY_FILE="/dev/stdin" sops --decrypt $tmp_encrypted_file
    )
    rm $tmp_encrypted_file  # Clean up temporary key file
    assert str contains $decrypted "username: dXNlcm5hbWU="
    assert str contains $decrypted "password: cGFzc3dvcmQ="
    assert str contains $decrypted "api_key: my-api-key"
}


export def "test keypair decrypt secret manifest" [] {
    # Setup
    let test_public_key: string = "age1hsrtxphk7exrdc0kt8dgr8a8r3hx88v3xpsw0ezaxvefsy9asegqknppc0"
    let test_private_key: string = "AGE-SECRET-KEY-12CC3A4LEDYF4S26UV6Z2MEG7ZQL9PTU5NHH6N3FN6FLJ5HACW9LQX0UWP2"
    let input_record: record = {
        apiVersion: v1,
        kind: Secret,
        metadata: { name: test-secret }
        data: {
            username: ('myusername' | encode base64)
            password: ('mypassword' | encode base64)
        }
    }

    # Encrypt
    let encrypted_record: record = (
        $input_record
        | to yaml
        | encrypt secret manifest $test_public_key
        | from yaml
    )

    # Decrypt
    let decrypted_record: record = (
        $encrypted_record
        | to yaml
        | keypair decrypt secret manifest $test_private_key
        | from yaml
    )

    # Test
    assert equal $input_record $decrypted_record
}
