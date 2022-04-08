#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC1091,SC2140
#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."
VTPM_EXEC="${ROOT}/vtpm-exec/vtpm-exec"

source "${ROOT}/common.sh"

check_root

check_vtpm_proxy_device

check_swtpm_tpm2_support

check_ima_support

check_auditd

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${ROOT}/check.sh" \
	"${DIR}/measure.sh"

if ! check_ns_measure_support; then
  echo " Error: IMA-ns does not support IMA-measurement"
  exit "${SKIP:-3}"
fi

copy_elf_busybox_container "$(which swtpm)"
copy_elf_busybox_container "$(which swtpm_ioctl)"
copy_elf_busybox_container "${VTPM_EXEC}" "bin/"

# The following test needs swtpm and ${VTPM_EXEC} copied
if ! check_ns_vtpm_support; then
  echo " Error: IMA-ns does not support vTPM"
  exit "${SKIP:-3}"
fi

# Test measurements caused by executable run in namespace

echo "INFO: Testing measurements in container equals number of PCRExtends for vTPM 2"

run_busybox_container_vtpm 1 ./measure.sh
rc=$?
if [ "${rc}" -ne 0 ] ; then
  echo " Error: Failed to create IMA namespace."
  exit "${rc}"
fi

echo "INFO: Pass test 1"

exit "${SUCCESS:-0}"
