#!/bin/bash

# This script is used to build the LCM library and use it in OSM

DOCKER_REPOSITORY="localhost:5000/opensourcemano"
VERSION="devel"
DIR="$(pwd)"

function build {
    # Build the LCM image and push it to the repository
    scripts/local-build.sh --no-cache --run-httpserver
    scripts/local-build.sh --no-cache --module common,LCM stage-2
    scripts/local-build.sh --no-cache --module LCM stage-3
    scripts/local-build.sh --no-cache --module LCM registry-push
}

function apply {
    # Update the OSM with the new LCM
    echo "Updating OSM with the new LCM"
    apply_status=$(kubectl patch deployment -n osm lcm --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Always"}, {"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "'$DOCKER_REPOSITORY'/lcm:'$VERSION'"}]')

    # If already up to date, restart the LCM pod to apply the changes
    if [ "$apply_status" == "deployment.apps/lcm patched" ]; then
        echo "LCM updated successfully"
    else
        # Restart the LCM pod
        echo "Image already up to date. Restarting the LCM pod to apply the changes"
        kubectl rollout restart -n osm deployment/lcm
    fi
}

function undo {
    # Use the default LCM image
    kubectl patch deployment -n osm lcm --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "IfNotPresent"}, {"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "opensourcemano/lcm:15"}]'
}


if [ "$1" == "apply" ]; then
    apply
elif [ "$1" == "build" ]; then
    if [ -z "$2" ]; then
        build
    elif [ "$2" == "apply" ]; then
        build
        apply
    else
        echo "Invalid argument. Please provide 'build' without any additional arguments."
    fi
elif [ "$1" == "undo" ]; then
    undo
else
    echo "Invalid argument. Please provide 'build', 'apply', 'build apply' or 'undo'."
fi
