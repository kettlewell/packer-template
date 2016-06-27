#!/bin/bash

OUTPUT=$1

if [ -z "$OUTPUT" ]; then
    echo "Usage: $0 <output file>"
    exit 1
fi

GIT_REVISION=$(git rev-parse HEAD)
DATE=$(date -R)

if hash packer.io 2>/dev/null; then
    PACKER_VERSION=$(packer.io --version)
elif hash packer 2>/dev/null; then
    PACKER_VERSION=$(packer --version)
else
    PACKER_VERSION='packer not found'
fi


echo "# Packer Template Info" > $OUTPUT
echo "git revision: $GIT_REVISION" >> $OUTPUT
echo "build date: $DATE" >> $OUTPUT
echo "packer version: $PACKER_VERSION" >> $OUTPUT
