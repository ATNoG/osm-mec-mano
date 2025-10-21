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

# Module with custom commands to create and manage age key pairs for SOPS encryption/decryption of Kubernetes secrets.


# Create a new age key pair
export def "create age" [
    age_key_name: string,
    credentials_dir?: path  # Optional, defaults to $env.CREDENTIALS_DIR
] {
    let dir: path = if $credentials_dir == null { $env.CREDENTIALS_DIR } else { $credentials_dir }
    let key_path: path = ({ parent: $dir, stem: $age_key_name, extension: "key"} | path join)
    let pub_path: path = ({ parent: $dir, stem: $age_key_name, extension: "pub"} | path join)

    # Delete existing keys
    rm -f $key_path $pub_path

    # Generate private key
    ^age-keygen -o $key_path

    # Extract public key
    ^age-keygen -y $key_path | save $pub_path
}

export alias create_age_keypair = create age


# In-place encrypt secrets in manifest
# -- NOT EXPORTED --
def "encrypt secret inplace" [
    file: path,
    public_key: string
]: [
    nothing -> nothing
] {
    ^sops --age $public_key --encrypt --encrypted-regex '^(data|stringData)$' --in-place $file
}

export alias encrypt_secret_inplace = encrypt secret inplace


# Encrypt with SOPS a manifest of Kubernetes secret received from stdin
export def "encrypt secret manifest" [public_key: string]: [
    string -> string
] {
    # Saves the input to preserve it from multiple invokes
    let manifest: string = $in

    # If the input empty, just returns an empty string
    if $manifest == "" {
        return ""
    }

    let tmp_file = (mktemp -t --suffix .yaml)
    $manifest | save -f $tmp_file

    ^sops --age $public_key --encrypt --encrypted-regex '^(data|stringData)$' --in-place $tmp_file

    let content: string = (open $tmp_file | to yaml)
    rm -f $tmp_file
    $content
}

export alias encrypt_secret_from_stdin = encrypt secret manifest


# Decrypt with SOPS a manifest of a Kubernetes secret received from stdin
export def "decrypt secret manifest" [private_key: string]: [
    string -> string
] {
    # Saves the input to preserve it from multiple invokes
    let encrypted_manifest: string = $in

    # If the input empty, just returns an empty string
    if $encrypted_manifest == "" {
        return ""
    }

    # Decrypt using temporary file
    let tmp_encrypted_file = (mktemp -t --suffix .yaml)
    $encrypted_manifest | save -f $tmp_encrypted_file
    let decrypted_manifest: string = (
        $private_key
        | SOPS_AGE_KEY_FILE="/dev/stdin" sops --decrypt $tmp_encrypted_file
    )
    rm $tmp_encrypted_file  # Clean up temporary key file

    # Returns the decrypted secret
    $decrypted_manifest
}
