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

# Module with helper functions to create strategic merge patches for Kubernetes resources (patchStrategicMerge).


# Helper to create a full strategic merge patch, including the target object specification and partial resource manifest.
#
# Example:
# $ strategicmergepatch create {kind: Deployment, name: podinfo} (
# 'apiVersion: apps/v1
# kind: Deployment
# metadata:
#   name: not-used
# spec:
#   template:
#       metadata:
#         annotations:
#           cluster-autoscaler.kubernetes.io/safe-to-evict: "true"' | from yaml
# ) | to yaml
#
# target:
#   kind: Deployment
#   name: podinfo
# patch: |
#   apiVersion: apps/v1
#   kind: Deployment
#   metadata:
#     name: not-used
#   spec:
#     template:
#       metadata:
#         annotations:
#           cluster-autoscaler.kubernetes.io/safe-to-evict: 'true'
#
# Further information about advanced syntax for strategic merge patch (e.g. '$patch' directives) can be found at <https://github.com/kubernetes/community/blob/master/contributors/devel/sig-api-machinery/strategic-merge-patch.md>
export def "create" [
    target: record, # Target resource specification as per <https://github.com/kubernetes-sigs/kustomize/blob/master/examples/patchMultipleObjects.md>
    patch: record   # Partial resource manifest
]: [
    nothing -> record
] {
    {
        target: $target,
        patch: ($patch | to yaml)
    }
}
