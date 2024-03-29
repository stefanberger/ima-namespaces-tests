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
  echo " Skip: IMA-ns does not support IMA-measurement"
  exit "${SKIP:-3}"
fi

copy_elf_busybox_container "$(which swtpm)"
copy_elf_busybox_container "$(which swtpm_ioctl)"
copy_elf_busybox_container "${VTPM_EXEC}" "bin/"
copy_elf_busybox_container "$(which dmesg)" "bin/"

# The following test needs swtpm and ${VTPM_EXEC} copied
if ! check_ns_vtpm_support; then
  echo " Skip: IMA-ns does not support vTPM"
  exit "${SKIP:-3}"
fi

# Test measurements caused by executable run in namespace

num=$(( $(nproc) * 5 ))

echo "INFO: Testing measurements in containers equals number of PCR_Extends for vTPM 2; starting ${num} containers"

# Children indicate failure by creating the failfile
rootfs="$(get_busybox_container_root)"
FAILFILE="/failfile"
failfile="${rootfs}/${FAILFILE}"

for ((i = 0; i < "${num}"; i++)); do
  NSID="${i}" FAILFILE="${FAILFILE}" \
    run_busybox_container_vtpm 1 ./measure.sh &
done

# Wait for all child processes
wait

if [ -f "${failfile}" ]; then
  echo " Error: Test failed in an IMA namespace"
  exit "${FAIL:-1}"
fi

echo "INFO: Pass test 1"

exit "${SUCCESS:-0}"
