#!/bin/bash
# ptf-py3 is a pure-Python wheel that SONiC builds from src/ptf-py3 + ptf-py3.patch; copy it out of the amd64 docker-ptf:202605
# image (no amd64 code is run) for images/docker-ptf/Dockerfile.add-ptf-py3
set -eu
id=$(docker create --platform linux/amd64 sonicdev-microsoft.azurecr.io:443/docker-ptf:202605)
docker export $id > /tmp/ptf202605.tar
docker rm $id >/dev/null
rm -rf x && mkdir x
tar -xf /tmp/ptf202605.tar -C x root/env-python3/lib/python3.11/site-packages/ptf root/env-python3/lib/python3.11/site-packages/ptf-0.10.0.post0.dist-info \
    root/env-python3/bin/ptf root/env-python3/bin/ptf_nn_agent.py
find x -name __pycache__ -prune -exec rm -rf {} +
tar -C x/root/env-python3 -cf ptf-files.tar lib bin
