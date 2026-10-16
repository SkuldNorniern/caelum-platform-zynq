#!/bin/sh
# same board side as the Vivado platform: <top>.bit + <top>.hwh from the v++ link, run under PYNQ
exec sh "$(dirname "$0")/../pynq-z2/run.sh"
