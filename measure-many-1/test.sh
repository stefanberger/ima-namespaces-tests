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

# requires check.sh
if ! check_ns_measure_support; then
  echo " Skip: IMA-ns does not support IMA-measure"
  exit "${SKIP:-3}"
fi

# Test measurements caused by executable run in many namespaces

num=$(( $(nproc) * 10 ))

echo "INFO: Testing measurements caused by executables in ${num} containers"

rootfs="$(get_busybox_container_root)"

# Children indicate failure by creating the failfile
FAILFILE="failfile"
failfile="${rootfs}/${FAILFILE}"

for ((i = 0; i < "${num}"; i++)); do
  NSID="${i}" FAILFILE="${FAILFILE}" \
    run_busybox_container ./measure.sh &
done

# Wait for all child processes
wait

if [ -f "${failfile}" ]; then
  echo " Error: Test failed in an IMA namespace"
  exit "${FAIL:-1}"
fi

echo "INFO: Pass test 1"

exit "${SUCCESS:-0}"
