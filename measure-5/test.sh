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
	"${DIR}/measure.sh"

if ! check_ns_measure_support; then
  echo " Skip: IMA-ns does not support IMA-measurement"
  exit "${SKIP:-3}"
fi

copy_elf_busybox_container "$(type -P evmctl)"

# Test meassurements caused by executables and libraries run in namespace

echo "INFO: Testing measuring (BPRM_CHECK + MMAP_CHECK) with different templates inside container"

run_busybox_container ./measure.sh
rc=$?
if [ $rc -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "$rc"
fi

echo "INFO: Pass test 1"

exit "${SUCCESS:-0}"
