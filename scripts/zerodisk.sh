#!/usr/bin/env bash
echo "Info: Zero out the free space to save space"
sync;sync

AVAIL=$(df --block-size=1M /|tail -1|awk '{print $4}')

dd if=/dev/zero of=/EMPTY conv=fsync bs=1M count=${AVAIL}
rm /EMPTY
sync;sync

