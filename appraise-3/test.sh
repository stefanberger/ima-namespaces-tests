#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC1091
#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_ima_support

setup_busybox_container \
	"${ROOT}/check.sh" \
	"${DIR}/child.sh" \
	"${DIR}/parent.sh" \
	"${ROOT}/ns-common.sh" \
	"${ROOT}/keys/rsakey.pem" \
	"${ROOT}/keys/rsa.crt"

if ! check_ns_appraise_support; then
  echo " Skip: IMA-ns does not support IMA-appraise"
  exit "${SKIP:-3}"
fi

copy_elf_busybox_container "$(type -P unshare)"
copy_elf_busybox_container "$(type -P keyctl)"
copy_elf_busybox_container "$(type -P evmctl)"
copy_elf_busybox_container "$(type -P getfattr)"
copy_elf_busybox_container "$(type -P setfattr)"

# Test that appraisal policy in parent container prevents execution in child container
echo "INFO: Testing appraisal policy in parent prevents execution of unsigned files in child"

run_busybox_container_nested \
  keyctl session - ./parent.sh \
    2> >(sed '/^Joined session.*/d')
rc=$?
if [ $rc -ne 0 ]; then
  echo " Error: Test failed in IMA namespace."
  exit "$rc"
fi

echo "INFO: Pass test 1"

exit "${SUCCESS:-0}"
