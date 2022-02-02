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
	"${DIR}/setxattr-check.sh" \
	"${ROOT}/keys/rsakey.pem"

copy_elf_busybox_container "$(type -P evmctl)"

# Test appraisal caused by executable run in namespace

echo "INFO: Testing appraisal policy with SEXATTR_CHECK rules inside container"

for ((algos = 1; algos <= 15; algos++)) {
  ALGOS=${algos} run_busybox_container ./setxattr-check.sh
  rc=$?
  if [ "${rc}" -ne 0 ] ; then
    echo " Error: Test failed in IMA namespace."
    exit "$rc"
  fi
}

echo "INFO: Pass"

exit "${SUCCESS:-0}"