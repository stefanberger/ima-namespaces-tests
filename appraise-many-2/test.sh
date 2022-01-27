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
	"${DIR}/appraise.sh" \
	"${ROOT}/keys/rsakey.pem" \
	"${ROOT}/keys/rsa.crt" \
	"${ROOT}/keys/rsakey2.pem" \
	"${ROOT}/keys/rsa2.crt"

# requires check.sh
if ! check_ns_appraise_support; then
  echo " Error: IMA-ns does not support IMA-appraise"
  exit "${SKIP:-3}"
fi

copy_elf_busybox_container "$(type -P keyctl)"
copy_elf_busybox_container "$(type -P evmctl)"
copy_elf_busybox_container "$(type -P getfattr)"
copy_elf_busybox_container "$(type -P setfattr)"

# Test appraisal of executables in many namespaces

num=$(( $(nproc) * 3 ))
maxkeys=$(get_max_number_keys)
# As non-root user we may run into key quota issues
num=$([ "${num}" -gt "${maxkeys}" ] && echo "$(((maxkeys - 64) / 3))" || echo "${num}")

echo "INFO: Maximum number of keys allowed: ${maxkeys}"
echo "INFO: Testing appraisal of executables in ${num} containers."

rootfs="$(get_busybox_container_root)"

# Children indicate failure by creating the failfile
FAILFILE="failfile"
failfile="${rootfs}/${FAILFILE}"

for ((i = 0; i < "${num}"; i++)); do
  NSID="${i}" FAILFILE="${FAILFILE}" NUM_CONTAINERS="${num}" \
    run_busybox_container_key_session ./appraise.sh &
done

# Wait for all child processes
wait

if [ -f "${failfile}" ]; then
  echo " Error: Test failed in an IMA namespace"
  exit "${FAIL:-1}"
fi

echo "INFO: Pass test 1"

exit "${SUCCESS:-0}"
