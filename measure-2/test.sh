#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC1091
#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_ima_support

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${ROOT}/check.sh" \
	"${DIR}/configure-ima-ns.sh"

if ! check_ns_measure_support; then
  echo " Error: IMA-ns does not support IMA-measure"
  exit "${SKIP:-3}"
fi

# Test measurements caused by executable run in namespace

echo "INFO: Testing configuration of IMA-ns with hash and template inside container"

for ((i = 0; i < 64; i++)) do
  ID=${i} run_busybox_container ./configure-ima-ns.sh
  rc=$?
  if [ $rc -ne 0 ] ; then
    echo " Error: Test failed in IMA namespace."
    exit "$rc"
  fi
done

echo "INFO: Pass"

exit "${SUCCESS:-0}"
