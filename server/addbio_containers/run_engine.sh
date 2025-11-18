#!/bin/bash

set -e

# Put your data in a folder with the suffix "_original" so that
# it can be copied into a fresh folder when processing. See the
# sample data in "opencap_test_original" for the expected data
# format.
DATA_PATH=${PWD}/opencap_test
rm -rf ${DATA_PATH}
cp -r ${DATA_PATH}_original ${DATA_PATH}

# This command mounts the data folder to the Docker container
# and runs the engine script on that data. Replace "nbianco/addbio"
# with your Docker image name if different.
docker run --rm -it \
    --platform linux/amd64 \
    -v ${DATA_PATH}:/test_data \
    kswami235/addbio \
    python3 engine/src/engine.py /test_data
