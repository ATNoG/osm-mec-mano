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

# Module with custom commands to generate `overlay patches`, i.e., patches to a Kustomization that references the resources that we intend to patch at runtime.


use ./patch.nu
use ./jsonpatch.nu
use ./strategicmergepatch.nu
use ./generator.nu


# Add overlay patch to Kustomization item (in a ResourceList) to modify a key in a referenced resource, using the JSON patch (patchJson6902) format
export def "add patch" [
    --ks-namespace: string,      # Namespace of the Kustomization
    kustomization_name: string,  # Kustomization to add the patch to
    target: record,              # Target resource for the patch, as per <https://github.com/kubernetes-sigs/kustomize/blob/master/examples/patchMultipleObjects.md>
    patch_value: record          # Patch content as record type. It can be a JSON patch (patchJson6902) or a Strategic Merge Patch
]: [
    record -> record
] {
    let in_resourcelist: record = $in

    let patch_content: record = (
        {
            target: $target,
            patch: ($patch_value | to yaml)
        }
    )

    $in_resourcelist
    | (patch list append item
        $.spec.patches
        $patch_content
        "kustomize.toolkit.fluxcd.io/v1"
        "Kustomization"
        $kustomization_name
        $ks_namespace
    )
}


# Add an overlay patch to a Kustomization item (in a ResourceList) to modify a key in a referenced resource, using the JSON patch (patchJson6902) format
# This command provides a user-friendly interface to create a JSON patch with exactly ONE operation
export def "add jsonpatch" [
    --ks-namespace: string,      # Namespace of the Kustomization
    --operation: string = "add", # Operation types: "add", "remove", "replace", "move", "copy", or "test", as per RFC6902
    kustomization_name: string,  # Kustomization to add the patch to
    target: record, # Target resource for the patch, as per <https://github.com/kubernetes-sigs/kustomize/blob/master/examples/patchMultipleObjects.md>
    path: string,   # JSON pointer path (format "/a/b/c") at the TARGET RESOURCE to be patched.
    value?: any     # Value to set in the target path (required for "add" and "replace" operations)
    from?: string,  # JSON pointer path (format "/a/b/c") at the TARGET RESOURCE to take as source in "copy" or "move" operations.
]: [
    record -> record
] {
    let in_resourcelist: record = $in

    let operation_spec: record = (
        if $operation in ["add", "replace"] {
            {
                op: $operation,
                path: $path,
                value: $value
            }
        } else if $operation in ["remove"] {
            {
                op: $operation,
                path: $path
            }
        } else if $operation in ["move", "copy"] {
            {
                op: $operation,
                from: $from,
                path: $path
            }
        } else {
            error make { msg: "Invalid operation type. Supported values are 'add', 'remove', 'replace', 'move', 'copy'. See RFC6902 for details" }
        }
    )

    let patch_content: record = (
        jsonpatch create
            $target
            $operation_spec
    )

    $in_resourcelist
    | (patch list append item
        $.spec.patches
        $patch_content
        "kustomize.toolkit.fluxcd.io/v1"
        "Kustomization"
        $kustomization_name
        $ks_namespace
    )
}


# Add a StrategicMergePatch to a Kustomization item (in a ResourceList) to modify a key in a referenced resource
# This command provides a user-friendly interface to create a patch
export def "add strategicmergepatch" [
    --ks-namespace: string,      # Namespace of the Kustomization
    kustomization_name: string,  # Kustomization to add the patch to
    target: record, # Target resource for the patch, as per <https://github.com/kubernetes-sigs/kustomize/blob/master/examples/patchMultipleObjects.md>
    patch: record,  # Contents of the strategic patch in the format of a record
]: [
    record -> record
] {
    let in_resourcelist: record = $in

    let patch_content: record = (
        strategicmergepatch create
            $target
            $patch
    )

    $in_resourcelist
    | (patch list append item
        $.spec.patches
        $patch_content
        "kustomize.toolkit.fluxcd.io/v1"
        "Kustomization"
        $kustomization_name
        $ks_namespace
    )
}


# Modify a referenced HelmRelease to add inline values via an overlay patch in a Kustomization (in a ResourceList)
export def "helmrelease add inline values" [
    --ks-namespace: string,      # Namespace of the Kustomization
    --hr-namespace: string,      # Namespace of the HelmRelease
    --operation: string = "add", # Allowed operation types: "add", "replace". Default is "add"
    kustomization_name: string,  # Kustomization to add the patch to
    helmrelease_name: string,    # HelmRelease to add the values to
    values: record     # Helm values to include inline in the HelmRelease spec
]: [
    record -> record
] {
    let in_resourcelist: record = $in

    # Exit if the operation is not supported
    if $operation not-in ["add", "replace"] {
        error make { msg: "Invalid operation type. Supported values are 'add', 'replace'. See RFC6902 for details" }
    }

    $in_resourcelist
    | (add jsonpatch
        --ks-namespace $ks_namespace
        --operation $operation
        $kustomization_name
        (
            if ($hr_namespace | is-empty) {
                { kind: "HelmRelease", name: $helmrelease_name }
            } else {
                { kind: "HelmRelease", name: $helmrelease_name, namespace: $hr_namespace }
            }
        )
        "/spec/values"
        $values
    )

}


# Modify a referenced HelmRelease to add values from a ConfigMap via an overlay patch in a Kustomization (in a ResourceList)
export def "helmrelease add values from configmap" [
    --ks-namespace: string,         # Namespace of the Kustomization
    --hr-namespace: string,         # Namespace of the HelmRelease
    --target-path: string,          # Optional `targetPath` to merge the values to (optional)
    --optional,                     # Optional flag to indicate if the values reference is optional
    kustomization_name: string,     # Kustomization to add the patch to
    helmrelease_name: string,       # HelmRelease to add the values to
    cm_name: string                 # ConfigMap to read the values from
    cm_key?: string = "values.yaml" # ConfigMap key to read the values from
]: [
    record -> record
] {
    let in_resourcelist: record = $in

    # Record to reference the values in the ConfigMap and, optionally, specify on how to merge them
    let full_reference: record = {
        kind: "ConfigMap",
        name: $cm_name,
        valuesKey: $cm_key
    }
    | (
        if ($target_path | is-empty) {
            $in
        } else {
            $in | insert targetPath $target_path
        }
    ) | (
        if $optional {
            $in | insert optional true
        } else {
            $in
        }
    )

    $in_resourcelist
    | (
        add strategicmergepatch
            --ks-namespace $ks_namespace
            $kustomization_name
            (
                if ($hr_namespace | is-empty) {
                    { kind: "HelmRelease", name: $helmrelease_name }
                } else {
                    { kind: "HelmRelease", name: $helmrelease_name, namespace: $hr_namespace }
                }
            )
            {
                apiVersion: "helm.toolkit.fluxcd.io/v2",
                kind: "HelmRelease",
                metadata: (
                    if ($hr_namespace | is-empty) {
                        { name: $helmrelease_name }
                    } else {
                        { name: $helmrelease_name, namespace: $hr_namespace }
                    }
                ),
                spec: {
                    valuesFrom: [
                        $full_reference
                    ]
                }
            }
    )
}

alias "helmrelease add values from cm" = helmrelease add values from configmap


# Modify a referenced HelmRelease to add values from a Secret via an overlay patch in a Kustomization (in a ResourceList)
export def "helmrelease add values from secret" [
    --ks-namespace: string,             # Namespace of the Kustomization
    --hr-namespace: string,             # Namespace of the HelmRelease
    --target-path: string,              # Optional `targetPath` to merge the values to (optional)
    --optional,                         # Optional flag to indicate if the values reference is optional
    kustomization_name: string,         # Kustomization to add the patch to
    helmrelease_name: string,           # HelmRelease to add the values to
    secret_name: string                 # Secret to read the values from
    secret_key?: string = "values.yaml" # Secret key to read the values from
]: [
    record -> record
] {
    let in_resourcelist: record = $in

    # Record to reference the values in the Secret and, optionally, specify on how to merge them
    let full_reference: record = {
        kind: "Secret",
        name: $secret_name,
        valuesKey: $secret_key
    }
    | (
        if ($target_path | is-empty) {
            $in
        } else {
            $in | insert targetPath $target_path
        }
    ) | (
        if $optional {
            $in | insert optional true
        } else {
            $in
        }
    )

    $in_resourcelist
    | (
        add strategicmergepatch
            --ks-namespace $ks_namespace
            $kustomization_name
            (
                if ($hr_namespace | is-empty) {
                    { kind: "HelmRelease", name: $helmrelease_name }
                } else {
                    { kind: "HelmRelease", name: $helmrelease_name, namespace: $hr_namespace }
                }
            )
            {
                apiVersion: "helm.toolkit.fluxcd.io/v2",
                kind: "HelmRelease",
                metadata: (
                    if ($hr_namespace | is-empty) {
                        { name: $helmrelease_name }
                    } else {
                        { name: $helmrelease_name, namespace: $hr_namespace }
                    }
                ),
                spec: {
                    valuesFrom: [
                        $full_reference
                    ]
                }
            }
    )
}


# Umbrella command to add values to a HelmRelease via an overlay patch to a Kustomization, using either inline values, a reference to a ConfigMap and/or a reference to a Secret.
# Parameters representing values (`inline_values`, `cm_name` or `secret_name`) that are empty will be skipped; only non-empty parameters will be used and add an overlay patch.
export def "helmrelease set values" [
    --ks-namespace: string,               # Namespace of the Kustomization
    --hr-namespace: string,               # Namespace of the HelmRelease (optional)
    --operation: string = "add",          # Allowed operation types: "add", "replace". Default is "add"
    --cm-key: string = "values.yaml",     # ConfigMap key to reference values from (default: "values.yaml")
    --cm-target-path: string,             # Optional targetPath for ConfigMap values
    --cm-optional,                        # Flag to mark ConfigMap values as optional (optional)
    --create-cm-with-values: record,      # Record with values to include in a new generated ConfigMap (default: empty, i.e., does not create a new ConfigMap).
    --secret-key: string = "values.yaml", # Secret key to reference values from (default: "values.yaml")
    --secret-target-path: string,         # Optional targetPath for Secret values
    --secret-optional,                    # Flag to mark Secret values as optional (optional)
    --create-secret-with-values: record,  # Record with values to include in a new generated Secret (default: empty, i.e., does not create a new Secret).
    --public-age-key: string              # Age key to encrypt the contents of the new Secret (if applicable)
    kustomization_name: string,           # Kustomization to add the patch to
    helmrelease_name: string,             # HelmRelease to modify
    inline_values?: record,               # Inline values to add to the HelmRelease spec (optional)
    cm_name?: string,                     # ConfigMap name to reference values from (optional)
    secret_name?: string                  # Secret name to reference values from (optional)
]: [
    record -> record
] {
    let in_resourcelist: record = $in

    # Validate operation type
    if $operation not-in ["add", "replace"] {
        error make { msg: "Invalid operation type. Supported values are 'add', 'replace'. See RFC6902 for details" }
    }

    # === Transformations ===
    $in_resourcelist
    # Add inline values if provided and not empty
    | if ($inline_values | is-empty) {
        $in
    } else {
        $in
        | (
            helmrelease add inline values 
                --ks-namespace $ks_namespace 
                --hr-namespace $hr_namespace
                --operation $operation
                $kustomization_name
                $helmrelease_name
                $inline_values
        )
    }
    # Add reference to ConfigMap-based values if cm_name is provided and not empty
    | if ($cm_name | is-empty) {
        $in
    } else {
        $in
        | (
            helmrelease add values from configmap 
                --ks-namespace $ks_namespace 
                --hr-namespace $hr_namespace
                --target-path $cm_target_path
                --optional=$cm_optional
                $kustomization_name 
                $helmrelease_name 
                $cm_name 
                $cm_key
        )
    }
    # Add reference to Secret-based values if secret_name is provided and not empty
    | if ($secret_name | is-empty) {
        $in
    } else {
        $in
        | (
            helmrelease add values from secret 
                --ks-namespace $ks_namespace
                --hr-namespace $hr_namespace
                --target-path $secret_target_path
                --optional=$secret_optional
                $kustomization_name 
                $helmrelease_name 
                $secret_name 
                $secret_key
        )
    }
    # Generate a ConfigMap if required
    | if ($create_cm_with_values | is-empty) or ($cm_name | is-empty) {
        $in
    } else {
        $in
        | (
            generator configmap
                --filename $"($cm_name).yaml"
                { $cm_key: ($create_cm_with_values | to yaml | str trim)}
                $cm_name
                ($hr_namespace | default "default")
        )
    }
    # Generate a Secret if required
    | if ($create_secret_with_values | is-empty) or ($secret_name | is-empty) {
        $in        
    } else {
        # If there is an age key, it is used to encrypt the secret manifest; otherwise, it is kept clear
        if ($public_age_key | is-empty) {
            $in
            | (
                generator secret
                    --filename $"($secret_name).yaml"
                    { $secret_key: ($create_secret_with_values | to yaml | str trim)}
                    $secret_name
                    ($hr_namespace | default "default")
            )
        } else {
            $in
            | (
                generator secret
                    --filename $"($secret_name).yaml"
                    --public-age-key $public_age_key
                    { $secret_key: ($create_secret_with_values | to yaml  | str trim)}
                    $secret_name
                    ($hr_namespace | default "default")
            )
        }
    }
}
