#!/usr/bin/env bash

set -exo pipefail

UDID=$(system_profiler SPUSBDataType | sed -n -E -e '/(iPhone|iPad)/,/Serial/s/ *Serial Number: *(.+)/\1/p')
PORT=12345
RESOLUTION="400x600"

./xcode/Debug/ios_minicap \
    --udid 921dedea5c5c8448dc36654575a35df1f51f4026 \
    --port $PORT \
    --resolution $RESOLUTION

    # ./build/ios_minicap \
    # --udid $UDID \
    # --port $PORT \
    # --resolution $RESOLUTION
