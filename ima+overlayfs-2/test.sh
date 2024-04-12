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
	"${DIR}/writers.sh"

#kv=$(get_kernel_version)
#if ! kernel_version_ge "${kv}" "6.9.0"; then
#  echo " Skip: EVM on overlayfs was only supported starting in 6.9.0"
#  exit "${SKIP:-3}"
#fi

copy_elf_busybox_container "$(type -P keyctl)"

echo "INFO: Testing IMA violations with overlayfs"

run_busybox_container_key_session ./writers.sh
rc=$?
if [ $rc -ne 0 ] ; then
  echo " Error: Test failed."
  exit "$rc"
fi

echo "INFO: Success"

exit "${SUCCESS:-0}"
