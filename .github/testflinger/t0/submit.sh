#!/bin/bash
# Submit the job and return once its test phase starts; setup or provisioning that fails or overruns is retried.
set -u
job=$1 limit=$((${PROVISION_LIMIT:-25} * 60)) retries=${RETRIES:-2} poll=${POLL:-30}
id=""
trap '[ -z "$id" ] || testflinger cancel "$id"; exit 130' INT TERM
for attempt in $(seq 0 "$retries"); do
    id=$(testflinger submit --quiet "$job") || exit 1
    echo "id=$id" > "$GITHUB_OUTPUT"
    echo "::notice::Testflinger job $id (attempt $((attempt + 1)) of $((retries + 1)))"
    since=""
    while :; do
        state=$(testflinger status "$id") || state=""
        case "$state" in
            provision)
                since=${since:-$SECONDS}
                if [ $((SECONDS - since)) -ge "$limit" ]; then
                    echo "::warning::$id has been provisioning for over $((limit / 60)) minutes; cancelling it"
                    break
                fi ;;
            test|allocate|allocated|reserve|cleanup|complete|completed|cancelled) break ;;
            # Anything else is still on its way to provisioning, e.g. "running": an agent has taken the job.
            *) ;;
        esac
        sleep "$poll"
    done
    [ "$state" != test ] || exit 0
    if testflinger results "$id" | jq -e '.setup_status == 0 and .provision_status == 0' >/dev/null; then
        exit 0
    fi
    echo "::error::$id did not get through setup and provisioning ($state)"
    testflinger cancel "$id" >/dev/null 2>&1 || true
done
exit 1
