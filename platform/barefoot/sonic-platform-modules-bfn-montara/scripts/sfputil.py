#!/bin/bash

DOCKER_EXEC_FLAGS="i"

# Determine whether stdout is on a terminal
if [ -t 1 ] ; then
    DOCKER_EXEC_FLAGS+="t"
fi

docker exec -$DOCKER_EXEC_FLAGS syncd sfputil.py "$@"
