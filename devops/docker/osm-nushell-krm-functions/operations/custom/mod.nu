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

# Placeholder module for supporting custom transformations

# Import SDK modules
use ../../krm *
use ../location.nu


# Placeholder for a custom "create" transformation for a Brick of `custom`, `custom-hr`, or `full-custom` types, to be applied to the ResourceList received from stdin.
# - If the Brick is of `custom` type, a `basic` Brick transformation will be applied right before in the pipeline.
# - If the Brick is of `custom-hr` type, a `helmreleaseset` Brick transformation will be applied right before in the pipeline.
# - If the Brick is of `full-custom` type, only this transformation will be applied to the original ResourceList.
export def "create" [
    brick: record  # Brick specification
    environment: record = {}    # Record with environment variables to load
]: [
    record -> record
] {
    let rl: record = $in

    # Get the key parts
    let brick_name: string = ($brick | get -i name | default "untitled-brick")
    let brick_type: string = ($brick | get -i type | default "basic" | str downcase)
    let kustomization_name: string = ($brick | get $.kustomization.name)
    let kustomization_namespace: string = ($brick | get -i $.kustomization.namespace | default "flux-system")

    # Here would come your custom transformations over `rl`
    # . . .
    print $"Here we are applying a custom `create` transformation of '($brick_type)' type."
    # The print above is just informative. Please remove in your final custom transformation.

    # Here we should return the result of the custom transformations.
    # For the sake of the example, let's return just the original ResouceList with no transformations
    $rl
}


# Placeholder for a custom "update" transformation for a Brick of `custom`, `custom-hr`, or `full-custom` types, to be applied to the ResourceList received from stdin.
# - If the Brick is of `custom` type, a `basic` Brick transformation will be applied right before in the pipeline.
# - If the Brick is of `custom-hr` type, a `helmreleaseset` Brick transformation will be applied right before in the pipeline.
# - If the Brick is of `full-custom` type, only this transformation will be applied to the original ResourceList.
export def "update" [
    brick: record  # Brick specification
    environment: record = {}    # Record with environment variables to load
]: [
    record -> record
] {
    let rl: record = $in

    # Get the key parts
    let brick_name: string = ($brick | get -i name | default "untitled-brick")
    let brick_type: string = ($brick | get -i type | default "basic" | str downcase)
    let kustomization_name: string = ($brick | get $.kustomization.name)
    let kustomization_namespace: string = ($brick | get -i $.kustomization.namespace | default "flux-system")

    # Here would come your custom transformations over `rl`
    # . . .
    print $"Here we are applying a custom `update` transformation of '($brick_type)' type."
    # The print above is just informative. Please remove in your final custom transformation.

    # Here we should return the result of the custom transformations.
    # For the sake of the example, let's return just the original ResouceList with no transformations
    $rl
}


# Placeholder for a custom "delete" transformation for a Brick of `custom`, `custom-hr`, or `full-custom` types, to be applied to the ResourceList received from stdin.
# - If the Brick is of `custom` type, a `basic` Brick transformation will be applied right before in the pipeline.
# - If the Brick is of `custom-hr` type, a `helmreleaseset` Brick transformation will be applied right before in the pipeline.
# - If the Brick is of `full-custom` type, only this transformation will be applied to the original ResourceList.
export def "delete" [
    brick: record  # Brick specification
    environment: record = {}    # Record with environment variables to load
]: [
    record -> record
] {
    let rl: record = $in

    # Get the key parts
    let brick_name: string = ($brick | get -i name | default "untitled-brick")
    let brick_type: string = ($brick | get -i type | default "basic" | str downcase)
    let kustomization_name: string = ($brick | get $.kustomization.name)
    let kustomization_namespace: string = ($brick | get -i $.kustomization.namespace | default "flux-system")

    # Here would come your custom transformations over `rl`
    # . . .
    print $"Here we are applying a custom `delete` transformation of '($brick_type)' type."
    # The print above is just informative. Please remove in your final custom transformation.

    # Here we should return the result of the custom transformations.
    # For the sake of the example, let's return just the original ResouceList with no transformations
    $rl
}
