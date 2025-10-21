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

# Module with helper functions to create JSON patches for Kubernetes resources as per RFC6902 (patchJson6902).


# Helper function to create an operation for a JSON patch (patchJson6902) as per RFC6902
#
# Example:
# $ jsonpatch create operation add /spec/template/spec/securityContext {runAsUser: 10000, fsGroup: 1337} | to yaml
#
# op: add
# path: /spec/template/spec/securityContext
# value:
#   runAsUser: 10000
#   fsGroup: 1337
export def "create operation" [
    op: string,    # Operation type: "add", "remove", "replace", "move", "copy", or "test"
    path: string,  # JSON pointer path at the target key location in format "/a/b/c"
    value?: any    # Value to be added, replaced, or removed
    from?: string,  # JSON pointer path (format "/a/b/c") at the TARGET RESOURCE to take as source in "copy" or "move" operations.
]: [
    nothing -> record
] {
    if $op in ["add", "replace"] {
        if not ($value | is-empty) {
            {
                op: $op,
                path: $path,
                value: $value
            }
        } else {
            error make { msg: "Value is required for 'add' and 'replace' operations." }
        }
    } else if $op in ["remove"] {
        {
            op: $op,
            path: $path
        }
    } else if $op in ["move", "copy"] {
        if not ($from | is-empty) {
            {
                op: $op,
                from: $from,
                path: $path
            }
        } else {
            error make { msg: "Source path is required for 'move' and 'copy' operations." }
        }
    } else {
        error make { msg: "Invalid operation type. Supported values are 'add', 'remove', 'replace', 'move', 'copy'. See RFC6902 for details." }
    }
}


# Helper to create a full JSON patch (patchJson6902), including the target object specification and a list of operations
#
# Example 1: Using records directly
# $ jsonpatch create {kind: Deployment, name: podinfo} {op: add, target: /spec/template/spec/securityContext, value: {runAsUser: 10000, fsGroup: 1337}} | to yaml
#
# target:
#   kind: Deployment
#   name: podinfo
# patch: |
#   - op: add
#     path: /spec/template/spec/securityContext
#     value:
#       runAsUser: 10000
#       fsGroup: 1337
#
# Example 2: Leveraging the operation helper function
# $ jsonpatch create {kind: Deployment, name: podinfo} (jsonpatch create operation add /spec/template/spec/securityContext {runAsUser: 10000, fsGroup: 1337}) | to yaml
#
# target:
#   kind: Deployment
#   name: podinfo
# patch: |
#   - op: add
#     path: /spec/template/spec/securityContext
#     value:
#       runAsUser: 10000
#       fsGroup: 1337
export def "create" [
    target: record, # Target resource specification as per <https://github.com/kubernetes-sigs/kustomize/blob/master/examples/patchMultipleObjects.md>
    ...operations: record # List of patch operations as per RFC6902
]: [
    nothing -> record
] {
    {
        target: $target,
        patch: ($operations | to yaml)
    }
}
