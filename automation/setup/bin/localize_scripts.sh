#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

SCRIPT_FILE=${1:-"$DIR/../../restart_all_services.sh"}
HOMEDIR=${2:-"\/root"}

if [ -f "$SCRIPT_FILE" ]; then
  sed -r s/'\$HOME'/$HOMEDIR/g "$SCRIPT_FILE" > "${SCRIPT_FILE%.*}"
else 
  echo "$SCRIPT_FILE does not exist"
fi 
