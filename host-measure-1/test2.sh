#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC1091
#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_root

check_ima_support

setup_busybox_host \
	"${ROOT}/ns-common.sh" \
	"${DIR}/remeasure.sh"

# Test measurements caused by executable run on host

echo "INFO: Testing re-measurements on host"

run_busybox_host ./remeasure.sh
rc=$?
if [ $rc -ne 0 ] ; then
  echo " Error: Test failed."
  exit "$rc"
fi

echo "INFO: Success"

exit "${SUCCESS:-0}"
