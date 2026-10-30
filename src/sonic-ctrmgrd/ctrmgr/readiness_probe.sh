#!/bin/bash
# This script is used by k8s to check the readiness of containers
# Check if the container is readiness or not, exit code 0 means readiness, others mean not readiness

#### exit code contract, k8s only cares zero or not none-zero, but we want to use none-zero code to indicate different error
# 0: readiness
# 1: if the hook script is python code, the default crash exit code is 1
# 2: supervisor start service doesn't exit normally
# other exit code: returned by post_check_script, define in the post_check_script, should not include 1,2

# check if the start service exists
# if the start service doesn't exist, do nothing
# if the start service exists, check if it exits normally
# if the start service doesn't exit normally, exit with code 2
pre_check_service_name="start"
if command -v supervisorctl >/dev/null; then
    no_process_string="ERROR (no such process)"
    service_status=$(supervisorctl status $pre_check_service_name)
    if [[ $service_status != *"$no_process_string"* ]] && [[ $(echo $service_status |awk '{print $2}') != 'EXITED' ]]; then
        exit 2
    fi
else
    # Rock containers run pebble: the one-shot start service is inactive once it has exited with code 0,
    # and error once it has exited with a non-zero code; an unknown service yields no state.
    # Unlike supervisord, pebble keeps the exit result, so a failed start service is not ready.
    # A failed pebble query is not ready either, as an unreachable supervisord is.
    if ! service_json=$(pebble services --format json $pre_check_service_name); then
        exit 2
    fi
    service_state=$(jq -r --arg n "$pre_check_service_name" '.services[$n].current // empty' <<< "$service_json")
    if [[ -n $service_state ]] && [[ $service_state != 'inactive' ]]; then
        exit 2
    fi
fi

# feature owner can add their own readiness check script
# check if the post_check_script exists
# if the post_check_script exists, run it
# if the post_check_script exits with non-zero code, exit with the code
post_check_script="/usr/bin/readiness_probe_hook"
if [ -x $post_check_script ]; then
    $post_check_script
    post_check_result=$?
    if [ $post_check_result != 0 ]; then
        exit $post_check_result
    fi
fi

exit 0
