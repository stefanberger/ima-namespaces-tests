#!/usr/bin/env bash

# shellcheck disable=SC1091
#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_ima_support

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${DIR}/measure.sh" \
	"${DIR}/remeasure.sh"

# Test measurements caused by executable run in namespace

echo "INFO: Testing measurements inside container"

run_busybox_container ./measure.sh
rc=$?
if [ $rc -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "$rc"
fi

echo "INFO: Pass test 1"

# Test re-measure using modified executable run in namespace

echo "INFO: Testing re-measuring inside container"

run_busybox_container ./remeasure.sh
rc=$?
if [ "$rc" -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "$rc"
fi

echo "INFO: Pass test 2"

exit "${SUCCESS:-0}"
