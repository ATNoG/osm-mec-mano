#!/bin/bash

# This script is used to build the LCM library and use it in OSM

DOCKER_REPOSITORY="magalhaesdit"
VERSION="latest"

function build {
    # Build the LCM image and push it to the repository
    echo "Building LCM"
    docker build -t $DOCKER_REPOSITORY/lcm:$VERSION -f devops/Dockerfile.lcm .
    docker push $DOCKER_REPOSITORY/lcm:$VERSION
    docker rmi $DOCKER_REPOSITORY/lcm:$VERSION
}

function apply {
    # Update the OSM with the new LCM
    echo "Updating OSM with the new LCM"
    kubectl patch deployment -n osm lcm --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Always"}, {"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "'$DOCKER_REPOSITORY'/lcm:'$VERSION'"}]'
}

function undo {
    # Rollout undo 1 step
    kubectl rollout undo -n osm deployment/lcm
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
