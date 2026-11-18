#!/usr/bin/env bash
# Calls one function of deploy/lib.sh for the install tests, so that a test
# drives the stack with the very commands the scripts use:
#
#   e2e/install/call.sh compose ps
#   e2e/install/call.sh s3 lsf target:bucket
#   e2e/install/call.sh list_backups
#
# The functions that talk to the backup target read it from the environment
# file, as the scripts do.
set -euo pipefail
# shellcheck source=deploy/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../../deploy/lib.sh"
need_root
case ${1:-} in
  s3 | list_backups | remote | target_name) load_target ;;
  '') die 'usage: e2e/install/call.sh <function of deploy/lib.sh> [arguments]' ;;
esac
"$@"
