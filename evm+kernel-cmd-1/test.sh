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
	"${ROOT}/scripts/uml_chroot.sh" \
	"${ROOT}/check.sh" \
	"${DIR}/appraise.sh" \
	"${ROOT}/keys/rsakey.pem" \
	"${ROOT}/keys/rsa.crt"

copy_elf_busybox_container "$(type -P keyctl)"
copy_elf_busybox_container "$(type -P evmctl)"
copy_elf_busybox_container "$(type -P getfattr)"

echo "INFO: Testing EVM HMAC creation when passing evm=fix on kernel command line"

UML_KERNEL_CMD="evm=fix ima_appraise=log" \
  run_busybox_container_key_session ./appraise.sh
rc=$?
if [ $rc -ne 0 ] ; then
  echo " Error: Test failed."
  exit "$rc"
fi

echo "INFO: Success"

exit "${SUCCESS:-0}"
