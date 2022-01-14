#!/usr/bin/env bash

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
  echo " Error: IMA-ns does not support IMA-measure"
  exit "${SKIP:-3}"
fi

before=$(grep -c "rootfs/bin/busybox2" "${AUDITLOG}")

# Test auditing caused by executable run in many namespaces

# Reduce likleyhood of log rotation by not creating too many...
num=$(( $(nproc) * 1 ))

echo "INFO: Testing audit messages caused by executable in ${num} containers"

while :; do
  # Accomodate the case where we have a host audit rule
  num_extra=0
  ctr=$(grep -c -E '^audit.*func=BPRM_CHECK .*MAY_EXEC' /sys/kernel/security/ima/policy)
  [ "${ctr}" -ne 0 ] && num_extra=1

  # Count lines in audit log for log rotation detection
  numlines1=$(grep -c ^ "${AUDITLOG}")

  rootfs="$(get_busybox_container_root)"

  # Children indicate failure by creating the failfile
  FAILFILE="failfile"
  failfile="${rootfs}/${FAILFILE}"

  for ((i = 0; i < "${num}"; i++)); do
    NSID="${i}" FAILFILE="${FAILFILE}" \
      run_busybox_container ./audit.sh &
  done

  # Wait for all child processes
  wait

  if [ -f "${failfile}" ]; then
    echo " Error: Test failed in an IMA namespace"
    exit "${FAIL:-1}"
  fi

  numlines2=$(grep -c ^ "${AUDITLOG}")
  if [ "${numlines2}" -lt "${numlines1}" ]; then
    echo " INFO: Repeating test due to audit log rotation"
    continue
  fi

  expected=$((before + num + num_extra))
  after=$(wait_num_entries "${AUDITLOG}" "rootfs/bin/busybox2" $((expected)) 30)
  if [ "${expected}" -ne "${after}" ]; then
    echo " Error: Wrong number of busybox2 entries in audit log."
    echo "        Expected $((expected)), found ${after}."
    exit "${FAIL:-1}"
  fi

  echo "INFO: Pass test 1"
  exit "${SUCCESS:-0}"
done

