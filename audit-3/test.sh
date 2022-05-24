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
	"${DIR}/reaudit.sh"

if ! check_ns_audit_support; then
  echo " Error: IMA-ns does not support IMA-audit"
  exit "${SKIP:-3}"
fi

# Test auditing caused by executable run in namespace

# Accomodate the case where we have a host audit rule
num_extra=0
ctr=$(grep -c -E '^audit.*func=BPRM_CHECK .*MAY_EXEC' /sys/kernel/security/ima/policy)
[ "${ctr}" -ne 0 ] && num_extra=1

rootfs=$(get_busybox_container_root)
before=$(grep -c "type=INTEGRITY_RULE .* file=\"${rootfs}/bin/busybox2\"" "${AUDITLOG}")

echo "INFO: Testing auditing caused by executable in container and re-auditing after file modification by host"

policy="audit func=BPRM_CHECK mask=MAY_EXEC uid=0 "

SYNCFILE="syncfile" POLICY=${policy} \
  run_busybox_container_set_policy "/mnt" "${policy}" ./reaudit.sh &
childpid=$!
rc=$?
if [ "${rc}" -ne 0 ] ; then
  echo " Error: Failed to create IMA namespace."
  exit "${rc}"
fi

expected=$((before + 1 + num_extra))
after=$(wait_num_entries "${AUDITLOG}" "type=INTEGRITY_RULE .* file=\"${rootfs}/bin/busybox2\"" $((expected)) 30)
if [ $((expected)) -ne "${after}" ]; then
  wait_child_exit_with_child_failure "${childpid}"
  echo " Error: Wrong number of busybox2 entries in audit log."
  echo "        Expected $((expected - before)) more log entries. Expected ${expected}, found ${after}."
  exit "${FAIL:-1}"
fi

syncfile="${rootfs}/syncfile"

if ! wait_for_file "${syncfile}" 50; then
  wait_child_exit_with_child_failure "${childpid}"
  echo " Error: Namespace did not write syncfile in time to order file modification"
  exit "${FAIL:-1}"
fi

echo >> "${rootfs}/bin/busybox2"

rm -f "${syncfile}"

if ! wait_for_file "${syncfile}" 50; then
  wait_child_exit_with_child_failure "${childpid}"
  echo " Error: Namespace did not write syncfile in time after executing modified file"
  exit "${FAIL:-1}"
fi

expected=$((before + 2 + num_extra))
after=$(wait_num_entries "${AUDITLOG}" "type=INTEGRITY_RULE .* file=\"${rootfs}/bin/busybox2\"" $((expected)) 30)
if [ $((expected)) -ne "${after}" ]; then
  wait_child_exit_with_child_failure "${childpid}"
  echo " Error: Wrong number of busybox2 entries in audit log."
  echo "        Expected $((expected - before)) more log entries. Expected ${expected}, found ${after}."
  exit "${FAIL:-1}"
fi

wait_child_exit_with_child_failure "${childpid}"

echo "INFO: Pass test 1"

exit "${SUCCESS:-0}"
