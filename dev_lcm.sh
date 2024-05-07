#!/bin/bash

# This script is used to build the LCM library and use it in OSM

DOCKER_REPOSITORY="magalhaesdit"
VERSION="latest"

function build {
    echo "Building LCM"
    docker build -t $DOCKER_REPOSITORY/lcm:$VERSION -f devops/Dockerfile.lcm .
    docker push $DOCKER_REPOSITORY/lcm:$VERSION
    docker rmi $DOCKER_REPOSITORY/lcm:$VERSION
}

function apply {

    if [ "$2" == "build" ]; then
        build
    fi

    # Update the OSM with the new LCM
    echo "Updating OSM with the new LCM"
    kubectl patch deployment -n osm lcm --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Always"}, {"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "'$DOCKER_REPOSITORY'/lcm:'$VERSION'"}]'

}

function undo {

    # Rollout undo 1 step
    kubectl rollout undo -n osm deployment/lcm
}


if [ "$1" == "apply" ]; then
    apply
elif [ "$1" == "undo" ]; then
    undo
else
    echo "Invalid argument. Please provide 'apply' or 'undo'."
fi
