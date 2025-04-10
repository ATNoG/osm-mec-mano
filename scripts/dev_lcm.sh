#!/bin/bash

# This script is used to build the LCM library and use it in OSM

DOCKER_REPOSITORY="localhost:5000/opensourcemano"
VERSION="devel"

function build {
    # Build the LCM image and push it to the repository
    scripts/local-build.sh --no-cache --run-httpserver
    scripts/local-build.sh --no-cache --module common,IM,LCM,NBI stage-2
    scripts/local-build.sh --no-cache --module LCM,NBI stage-3
    scripts/local-build.sh --no-cache --module LCM,NBI registry-push
}

function apply {
    # Update the OSM with the new LCM
    echo "Updating OSM with the new LCM"
    lcm_apply_status=$(kubectl patch deployment -n osm lcm --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Always"}, {"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "'$DOCKER_REPOSITORY'/lcm:'$VERSION'"}]')
    nbi_apply_status=$(kubectl patch deployment -n osm nbi --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Always"}, {"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "'$DOCKER_REPOSITORY'/nbi:'$VERSION'"}]')

    # If already up to date, restart the LCM pod to apply the changes
    if [ "$lcm_apply_status" == "deployment.apps/lcm patched" ]; then
        echo "LCM updated successfully"
    else
        # Restart the LCM pod
        echo "Image already up to date. Restarting the LCM pod to apply the changes"
        kubectl rollout restart -n osm deployment/lcm
    fi

    # If already up to date, restart the NBI pod to apply the changes
    if [ "$nbi_apply_status" == "deployment.apps/nbi patched" ]; then
        echo "NBI updated successfully"
    else
        # Restart the NBI pod
        echo "Image already up to date. Restarting the NBI pod to apply the changes"
        kubectl rollout restart -n osm deployment/nbi
    fi
}

function update {
    # Update the code inside the images
    docker build -f scripts/docker/Dockerfile.LCM -t $DOCKER_REPOSITORY/lcm:$VERSION .
    docker build -f scripts/docker/Dockerfile.NBI -t $DOCKER_REPOSITORY/nbi:$VERSION .

    # Push the updated image to the repository
    docker push $DOCKER_REPOSITORY/lcm:$VERSION
    docker push $DOCKER_REPOSITORY/nbi:$VERSION
}

function undo {
    # Use the default LCM image
    kubectl patch deployment -n osm lcm --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "IfNotPresent"}, {"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "opensourcemano/lcm:17"}]'
    kubectl patch deployment -n osm nbi --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "IfNotPresent"}, {"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "opensourcemano/nbi:17"}]'
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
elif [ "$1" == "update" ]; then
    if [ -z "$2" ]; then
        update
    elif [ "$2" == "apply" ]; then
        update
        apply
    else
        echo "Invalid argument. Please provide 'build' without any additional arguments."
    fi
elif [ "$1" == "undo" ]; then
    undo
else
    echo "Invalid argument. Please provide 'build', 'update, 'apply', 'build apply', 'update apply' or 'undo'."
fi
