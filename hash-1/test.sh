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
	"${ROOT}/uml_chroot.sh" \
	"${ROOT}/check.sh" \
	"${DIR}/hash.sh"

if ! check_ns_hash_support; then
  echo " Skip: IMA-ns does not support IMA-appraise hash rules"
  exit "${SKIP:-3}"
fi

copy_elf_busybox_container "$(type -P getfattr)"

# Test appraisal caused by executable run in namespace

echo "INFO: Testing appraisal inside container"

run_busybox_container ./hash.sh
rc=$?
if [ $rc -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "$rc"
fi

echo "INFO: Pass test 1"

exit "${SUCCESS:-0}"
