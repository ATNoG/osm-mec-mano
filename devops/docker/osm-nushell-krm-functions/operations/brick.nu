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

# Module with custom functions to manage the transformations and generations associated to the different types of Building Blocks supported by OSM.
#
# Supported Brick types are:
#
# - `basic`. Basic transformation of the ResourceList. It performs a cleanup and regularization of the target Kustomization (enforce the right path in the repo, ensure that `wait` is enabled, etc.), unless specified otherwise. In addition, it also supports the commonest transformations for a Kustomization, such as addition of optional components, extra labels and/or annotations, hot replacement of image names and tags, etc. For more details, check out the help for the `brick transform basic` command.
# - `helmreleaseset`. Transformations for a ResourceList with a set of HelmReleases, so that values injected into the specific HelmReleases. It is a superset of the `basic` Brick, and its transformations are applied right after the corresponding basic transformations. For more details, check out the help for the `brick transform helmreleaseset` command.
# - `custom`. Transformation of the ResourceList with a custom (user-provided) "create" transformation after a `basic` regularization is applied. For more details, check out the help for the `custom create` command.
# - `custom-hr`. Transformation of the ResourceList with a custom (user-provided) "create" transformation after a `helmreleaseset` transformation (including `basic` regularizations) is applied. For more details, check out the help for the `custom create` command.
# - `custom-full`. Transformation of the ResourceList with a custom (user-provided) "create" transformation. **No `basic` regularization is applied**, so any regularization (if needed) should be implemented in the custom command. For more details, check out the help for the `custom create` command.


use ../krm *
use ./location.nu
use custom


# Apply the `basic` transformation to ResourceList received from stdin according to the specification of the Brick.
# The `basic` Brick transformation just does a cleanup and regularization of the target Kustomization
export def "transform basic" [
    brick: record  # Brick specification
]: [
    record -> record
] {
    let rl: record = $in

    # Get the key parts
    let brick_name: string = ($brick | get -i name | default "untitled-brick")
    let kustomization_name: string = ($brick | get $.kustomization.name)
    let kustomization_namespace: string = ($brick | get -i $.kustomization.namespace | default "flux-system")
    let src: string = ($brick | get source | location from base path)
    let options: record = ($brick | get -i options | default {})
    ## Should it avoid path regularization?
    let keep_path: bool = ($options | get -i keep-path | default false)
    ## Should it avoid enforcing the wait?
    let enforce_wait: bool = ($options | get -i enforce-wait | default true)
    ## Should it avoid enforcing the prune?
    let enforce_prune: bool = ($options | get -i enforce-prune | default true)
    ## Should it enable (or append) some `components`?
    let components: list = ($options | get -i components | default [])
    ## Should it set or overwrite `targetNamespace`?
    let targetNamespace: string = ($options | get -i targetNamespace | default "")
    ## Should it overwrite `interval`?
    let interval: string = ($options | get -i interval | default "")
    ## Should it set or overwrite `retryInterval`?
    let retryInterval: string = ($options | get -i retryInterval | default "")
    ## Should it set or overwrite `serviceAccountName`?
    let serviceAccountName: string = ($options | get -i serviceAccountName | default "")
    ## Should it add custom `healthChecks`?
    let healthChecks: list = ($options | get -i healthChecks | default [])
    ## Should it add custom `healthCheckExprs`?
    let healthCheckExprs: list = ($options | get -i healthCheckExprs | default [])
    ## Should it set or overwrite a `namePrefix`?
    let namePrefix: string = ($options | get -i namePrefix | default "")
    ## Should it set or overwrite a `nameSuffix`?
    let nameSuffix: string = ($options | get -i nameSuffix | default "")
    ## Should it append additional `.metadata.labels` and `.spec.commonMetadata.labels`?
    let new_labels: record = ($options | get -i new_labels | default {})
    ## Should it append additional `.metadata.annotations` and `.spec.commonMetadata.annotations`?
    let new_annotations: record = ($options | get -i new_annotations | default {})
    ## Should it append additional `.spec.images` replacements?
    let images: list = ($options | get -i images | default [])

    # Transform as per the basic Brick model
    $rl
    # Path regularization, if applicable
    | if $keep_path { $in } else {
        $in
        | (
            patch resource update key
                $.spec.path $src
                "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
        )
    }
    # Enforce the wait, if applicable
    | if $enforce_wait {
        $in
        | (
            patch resource upsert key
                $.spec.wait $enforce_wait
                "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
        )
    } else { $in }
    # Enforce the prune, if applicable
    | if $enforce_prune {
        $in
        | (
            patch resource upsert key
                $.spec.prune $enforce_prune
                "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
        )
    } else { $in }
    # Enable (or append) some `components`, if applicable
    | if ($components | is-not-empty) {
        let tmp_rl: record = $in
        let existing_components: list = (
            $tmp_rl
            | (
                patch resource keep
                    "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
            )
            | get -i $.items.0.spec.components
            | default []
        )
        let all_components: list = ($existing_components ++ $components) | uniq

        $tmp_rl
        | (
            patch resource upsert key
                $.spec.components $all_components
                "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
        )
    } else { $in }
    # Set or overwrite `targetNamespace`, if applicable
    | if ($targetNamespace | is-not-empty) {
        $in
        | (
            patch resource upsert key
                $.spec.targetNamespace $targetNamespace
                "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
        )
    } else { $in }
    # Overwrite `interval`, if applicable
    | if ($interval | is-not-empty) {
        $in
        | (
            patch resource update key
                $.spec.interval $interval
                "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
        )
    } else { $in }
    # Set or overwrite `retryInterval`, if applicable
    | if ($retryInterval | is-not-empty) {
        $in
        | (
            patch resource upsert key
                $.spec.retryInterval $retryInterval
                "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
        )
    } else { $in }
    # Set or overwrite `serviceAccountName`, if applicable
    | if ($serviceAccountName | is-not-empty) {
        $in
        | (
            patch resource upsert key
                $.spec.serviceAccountName $serviceAccountName
                "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
        )
    } else { $in }
    # Enable (or append) some `healthChecks`, if applicable
    | if ($healthChecks | is-not-empty) {
        let tmp_rl: record = $in
        let existing_healthChecks: list = ($tmp_rl | get -i $.spec.healthChecks | default [])
        let all_healthChecks: list = ($existing_healthChecks ++ $healthChecks) | uniq

        $tmp_rl
        | (
            patch resource upsert key
                $.spec.healthChecks $all_healthChecks
                "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
        )
    } else { $in }
    # Enable (or append) some `healthCheckExprs`, if applicable
    | if ($healthCheckExprs | is-not-empty) {
        let tmp_rl: record = $in
        let existing_healthCheckExprs: list = ($tmp_rl | get -i $.spec.healthCheckExprs | default [])
        let all_healthCheckExprs: list = ($existing_healthCheckExprs ++ $healthCheckExprs) | uniq

        $tmp_rl
        | (
            patch resource upsert key
                $.spec.healthCheckExprs $all_healthCheckExprs
                "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
        )
    } else { $in }
    # Set or overwrite `namePrefix`, if applicable
    | if ($namePrefix | is-not-empty) {
        $in
        | (
            patch resource upsert key
                $.spec.namePrefix $namePrefix
                "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
        )
    } else { $in }
    # Set or overwrite `nameSuffix`, if applicable
    | if ($nameSuffix | is-not-empty) {
        $in
        | (
            patch resource upsert key
                $.spec.nameSuffix $nameSuffix
                "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
        )
    } else { $in }
    # Enable (or append) some `.metadata.labels` and `.spec.commonMetadata.labels`, if applicable
    | if ($new_labels | is-not-empty) {
        let tmp_rl: record = $in
        let existing_labels: list = ($tmp_rl | get -i $.metadata.labels | default [])
        let existing_common_labels: list = ($tmp_rl | get -i $.spec.commonMetadata.labels | default [])
        let all_labels: list = ($existing_labels | merge $new_labels)
        let all_common_labels: list = ($existing_common_labels | merge $new_labels)

        $tmp_rl
        | (
            patch resource upsert key
                $.metadata.labels
                $all_labels
                "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
        )
        | (
            patch resource upsert key
                $.spec.commonMetadata.labels
                $all_common_labels
                "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
        )
    } else { $in }
    # Enable (or append) some `.metadata.annotations` and `.spec.commonMetadata.annotations`, if applicable
    | if ($new_annotations | is-not-empty) {
        let tmp_rl: record = $in
        let existing_annotations: list = ($tmp_rl | get -i $.metadata.annotations | default [])
        let existing_common_annotations: list = ($tmp_rl | get -i $.spec.commonMetadata.annotations | default [])
        let all_annotations: list = ($existing_annotations | merge $new_annotations)
        let all_common_annotations: list = ($existing_common_annotations | merge $new_annotations)

        $tmp_rl
        | (
            patch resource upsert key
                $.metadata.annotations
                $all_annotations
                "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
        )
        | (
            patch resource upsert key
                $.spec.commonMetadata.annotations
                $all_common_annotations
                "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
        )
    } else { $in }
    # Enable (or append) some `.spec.images` replacements, if applicable
    | if ($images | is-not-empty) {
        let tmp_rl: record = $in
        let existing_images: list = ($tmp_rl | get -i $.spec.images | default [])
        let all_images: list = ($existing_images ++ $images) | uniq

        $tmp_rl
        | (
            patch resource upsert key
                $.spec.images $all_images
                "kustomize.toolkit.fluxcd.io/v1" Kustomization $kustomization_name $kustomization_namespace
        )
    } else { $in }
}


# Apply the `helmreleaseset` transformation to ResourceList received from stdin according to the specification of the Brick.
# The `basic` Brick transformation just does a cleanup and regularization of the target Kustomization
export def "transform helmreleaseset" [
    brick: record  # Brick specification
]: [
    record -> record
] {
    # Input ReleaseList after basic transformations
    let rl: record = $in

    # Get the key parts
    let brick_name: string = ($brick | get -i name | default "untitled-brick")
    let kustomization_name: string = ($brick | get $.kustomization.name)
    let kustomization_namespace: string = ($brick | get -i $.kustomization.namespace | default "flux-system")
    let hrset_values: list<record> = ($brick | get "hrset-values" | default [])
    let public_age_key: string = ($brick | get -i $.public-age-key | default "")

    # Apply HelmRelease-specific transformations
    $hrset_values
    | reduce --fold $rl {|elt, acc|
        $acc
        | (
            overlaypatch helmrelease set values
                # --ks-namespace: string
                --ks-namespace $kustomization_namespace
                # --hr-namespace: string
                --hr-namespace ($elt | get $.HelmRelease.namespace)
                # --operation: string = "add"
                # --cm-key: string = "values.yaml"
                --cm-key ($elt | get -i $.valuesFrom.configMapKeyRef.key | default "values.yaml")
                # --cm-target-path: string
                # --cm-optional
                # --create-cm-with-values: record
                --create-cm-with-values ($elt | get -i "create-cm" | default {})
                # --secret-key: string = "values.yaml"
                --secret-key ($elt | get -i $.valuesFrom.secretKeyRef.key | default "values.yaml")
                # --secret-target-path: string
                # --secret-optional
                # --create-secret-with-values: record
                --create-secret-with-values (
                    $env
                    | get -i ($elt | get -i $.create-secret.env-values-reference | default "")
                    | default {}
                )
                # --public-age-key: string
                --public-age-key $public_age_key
                # kustomization_name: string
                $kustomization_name
                # helmrelease_name: string
                ($elt | get $.HelmRelease.name)
                # inline_values?: record
                ($elt | get -i "inline-values" | default {})
                # cm_name?: string
                ($elt | get -i $.valuesFrom.configMapKeyRef.name | default "")
                # secret_name?: string
                ($elt | get -i $.valuesFrom.secretKeyRef.name | default "")
        )
    }
}


# Transform the ResourceList received from stdin according to the specification of a Brick transformation.
#
export def transform [
    brick: record  # Brick specification
    environment: record = {}    # Record with environment variables to load
]: [
    record -> record
] {
    # Get input ResourceList
    let rl: record = $in

    # Get the brick name
    let brick_name: string = ($brick | get -i name | default "untitled-brick")

    # Update the environment to include the brick name
    let updated_environment: record = (
        $environment
        | upsert $.BRICK_NAME $brick_name
    )

    # Update the brick record accordingly
    let updated_brick: record = (
        $brick
        | replace vars $updated_environment
    )

    # Get other key parts
    let brick_type: string = ($updated_brick | get -i type | default "basic" | str downcase)

    # Apply transformation according to the brick type
    with-env $updated_environment {
        match $brick_type {
            "basic" => {
                # Basic transformation of the ResourceList (just cleanup and regularization)
                $rl
                | transform basic $updated_brick
            },
            "helmreleaseset" => {
                # Transformation of the ResourceList with a set of HelmReleases
                $rl
                | transform basic $updated_brick
                | transform helmreleaseset $updated_brick
            },
            "custom-full" => {
                # Transformation of the ResourceList with a custom "create" transformation
                $rl
                | custom brick create $updated_brick $updated_environment
            },
            "custom" => {
                # Transformation of the ResourceList with a custom "create" transformation, after a basic cleanup and regularization
                $rl
                | transform basic $updated_brick
                | custom brick create $updated_brick $updated_environment
            },
            "custom-hr" => {
                # Transformation of the ResourceList with a custom "create" transformation, after a `helmreleaseset` transformation
                $rl
                | transform basic $updated_brick
                | transform helmreleaseset $updated_brick
                | custom brick create $updated_brick $updated_environment
            },
            _ => {
                # Unknown brick type, throw an error
                error make { msg: $"Error: Unknown Brick type: ($updated_brick | get type)" }
            }
        }
    }
}
