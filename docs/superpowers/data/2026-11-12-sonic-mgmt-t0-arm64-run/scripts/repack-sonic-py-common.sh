#!/bin/bash
# The arm64 docker-sonic-mgmt build needs upstream's sonic_py_common wheel (pure Python, includes sonic_grpc; the resolute
# fork's copy lacks sonic_grpc). Rebuild the wheel from the files installed in the amd64 registry image.
# Run in the docker-sonic-mgmt build context; writes python-wheels/sonic_py_common-1.0-py3-none-any.whl
set -eu
IMG=sonicdev-microsoft.azurecr.io:443/docker-sonic-mgmt:latest
SP=/opt/venv/lib/python3.12/site-packages
id=$(docker create --platform linux/amd64 $IMG)
rm -rf whl && mkdir whl
docker export $id | tar -x -C whl --strip-components=5 \
    opt/venv/lib/python3.12/site-packages/sonic_py_common opt/venv/lib/python3.12/site-packages/sonic_grpc \
    opt/venv/lib/python3.12/site-packages/sonic_py_common-1.0.dist-info
docker rm $id >/dev/null
rm -f whl/sonic_py_common-1.0.dist-info/{INSTALLER,direct_url.json,REQUESTED}
find whl -name __pycache__ -prune -exec rm -rf {} +
mkdir -p python-wheels
(cd whl && python3 -m zipfile -c ../python-wheels/sonic_py_common-1.0-py3-none-any.whl sonic_py_common sonic_grpc sonic_py_common-1.0.dist-info)
