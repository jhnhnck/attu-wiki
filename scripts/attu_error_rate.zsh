#!/usr/bin/env zsh
# Attu Project Wiki - Error rate monitoring script wrapper
# This file is licensed under the MIT License; See LICENSE for full text.

SCRIPT_SOURCE=${0%/*}
cd $SCRIPT_SOURCE/..

source .venv/bin/activate && python ./scripts/attu_error_rate.py

exit
