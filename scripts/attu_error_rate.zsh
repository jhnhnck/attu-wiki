#!/usr/bin/env zsh

SCRIPT_SOURCE=${0%/*}
cd $SCRIPT_SOURCE/..

source ./scripts/.venv/bin/activate && python ./scripts/attu_error_rate.py

exit
