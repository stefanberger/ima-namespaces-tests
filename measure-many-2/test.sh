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
  echo " Error: IMA-ns does not support IMA-measure"
  exit "${SKIP:-3}"
fi

copy_elf_busybox_container "$(type -P unshare)"

# Test measurements caused by executable run in many namespaces

echo "INFO: Testing measurements caused by executables in containers"

rootfs="$(get_busybox_container_root)"

DEPTH="1" MAXDEPTH="32" POLICYDEPTH="32" \
  run_busybox_container_nested ./measure.sh
rc=$?
if [ "${rc}" -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "${rc}"
fi

echo "INFO: Pass test 1"

exit "${SUCCESS:-0}"
