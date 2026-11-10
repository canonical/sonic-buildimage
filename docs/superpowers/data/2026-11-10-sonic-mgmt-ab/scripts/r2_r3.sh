#!/bin/bash
# R2: new branch on the Dockerfile image; R3: unmodified upstream 202605 on the same image.
~/scratch/mgmt-ab/run_ab.sh sonic-mgmt R2-df > ~/scratch/mgmt-ab/R2-df.log 2>&1
# memory_checker restarts monit at teardown; upstream's sanity rejects the 10-minute Waiting that follows
sleep 660
~/scratch/mgmt-ab/run_ab.sh sonic-mgmt-upstream R3-df-upstream > ~/scratch/mgmt-ab/R3-df-upstream.log 2>&1
echo "r2_r3 done $(date -Is)"
