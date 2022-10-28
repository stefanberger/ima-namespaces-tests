#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC1091
#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_root

check_ima_support

check_auditd

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${ROOT}/check.sh" \
	"${DIR}/audit.sh"

# requires check.sh
if ! check_ns_audit_support; then
  echo " Error: IMA-ns does not support IMA-audit"
  exit "${SKIP:-3}"
fi

# Test auditing caused by executable run in many namespaces

# Reduce likleyhood of log rotation by not creating too many...
num=$(( $(nproc) * 1 ))

echo "INFO: Testing audit messages caused by executable in ${num} containers"

while :; do
  rootfs=$(get_busybox_container_root)
  before=$(grep -c "file=\"${rootfs}/bin/busybox2\"" "${AUDITLOG}")

  # Accomodate the case where we have a host audit rule
  num_extra=0
  ctr=$(grep -c -E '^audit.*func=BPRM_CHECK .*MAY_EXEC' "${SECURITYFS_MNT}/ima/policy")
  [ "${ctr}" -ne 0 ] && num_extra=1

  # Count lines in audit log for log rotation detection
  auditlog_size_1=$(get_auditlog_size)

  # Children indicate failure by creating the failfile
  FAILFILE="failfile"
  failfile="${rootfs}/${FAILFILE}"

  policy='audit func=BPRM_CHECK mask=MAY_EXEC uid=0 '

  for ((i = 0; i < "${num}"; i++)); do
    NSID="${i}" FAILFILE="${FAILFILE}" SYNCFILE="syncfile-${i}" \
      run_busybox_container_set_policy "/mnt" "${policy}" ./audit.sh &
  done

  # Wait for all child processes
  wait

  if [ -f "${failfile}" ]; then
    echo " Error: Test failed in an IMA namespace"
    exit "${FAIL:-1}"
  fi

  auditlog_size_2=$(get_auditlog_size)
  if [ "${auditlog_size_2}" -lt "${auditlog_size_1}" ]; then
    echo " INFO: Repeating test due to audit log rotation"
    continue
  fi

  expected=$((before + num + num_extra))
  after=$(wait_num_entries "${AUDITLOG}" "file=\"${rootfs}/bin/busybox2\"" $((expected)) 30)
  if [ "${expected}" -ne "${after}" ]; then
    echo " Error: Wrong number of busybox2 entries in audit log."
    echo "        Expected $((expected)), found ${after}."
    exit "${FAIL:-1}"
  fi

  echo "INFO: Pass test 1"
  exit "${SUCCESS:-0}"
done
