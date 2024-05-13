#!/bin/bash

# This script is used to build the LCM library and use it in OSM

DOCKER_REPOSITORY="magalhaesdit"
VERSION="latest"

function build {
    # Build the LCM image and push it to the repository
    echo "Building LCM"
    docker build -t $DOCKER_REPOSITORY/lcm:$VERSION -f devops/Dockerfile.lcm .
    docker push $DOCKER_REPOSITORY/lcm:$VERSION
    # docker rmi $DOCKER_REPOSITORY/lcm:$VERSION    # Comment this line for keeping the image locally
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
    if [ -z "$2" ]; then
        apply
    elif [ "$2" == "build" ]; then
        build
        apply
    else
        echo "Invalid argument. Please provide 'apply' or 'apply build'."
    fi
    
elif [ "$1" == "undo" ]; then
    undo
else
    echo "Invalid argument. Please provide 'apply' or 'undo'."
fi
