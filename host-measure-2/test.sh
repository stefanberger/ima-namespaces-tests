#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC1091
#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_ima_support

setup_busybox_host \
	"${ROOT}/ns-common.sh" \
	"${ROOT}/scripts/uml_chroot.sh" \
	"${DIR}/measure.sh"

copy_elf_busybox_container "$(type -P evmctl)"

# Test measurements caused by executables and libraries run in namespace

echo "INFO: Testing measuring (BPRM_CHECK + MMAP_CHECK) with different templates on host"

run_busybox_host ./measure.sh
rc=$?
if [ $rc -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "$rc"
fi

echo "INFO: Success"

exit "${SUCCESS:-0}"
