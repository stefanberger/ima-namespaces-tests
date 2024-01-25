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

# evm-sig was added in 5.14
kv=$(get_kernel_version)
if ! kernel_version_ge "${kv}" "5.14.0"; then
  echo " Skip: Requiring Linux 5.14.0 or order for evm-sig support"
  exit "${SKIP:-3}"
fi
if ! check_ns_evm_support; then
  echo " Skip: IMA-ns does not support EVM in namespaces"
  exit "${SKIP:-3}"
fi
if ! check_ns_appraise_support; then
  echo " Skip: IMA-ns does not support IMA-appraisal in namespaces"
  exit "${SKIP:-3}"
fi

copy_elf_busybox_container "$(type -P keyctl)"
copy_elf_busybox_container "$(type -P evmctl)"
copy_elf_busybox_container "$(type -P getfattr)"

echo "INFO: Testing EVM signature appraisal and evm-sig template"

run_busybox_container_key_session ./appraise.sh
rc=$?
if [ $rc -ne 0 ] ; then
  echo " Error: Test failed."
  exit "$rc"
fi

echo "INFO: Success"

exit "${SUCCESS:-0}"
