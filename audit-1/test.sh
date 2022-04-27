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
	"${DIR}/audit.sh" \
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
before=$(grep -c "file=\"${rootfs}/bin/busybox2\"" "${AUDITLOG}")

echo "INFO: Testing auditing caused by executable in container"

policy="audit func=BPRM_CHECK mask=MAY_EXEC uid=0 gid=0 fowner=0 fgroup=0 "

SYNCFILE="syncfile" POLICY=${policy} \
  run_busybox_container_set_policy "/mnt" "${policy}" ./audit.sh
rc=$?
if [ "${rc}" -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "${rc}"
fi

expected=$((before + 1 + num_extra))
after=$(wait_num_entries "${AUDITLOG}" "file=\"${rootfs}/bin/busybox2\"" $((expected)) 30)
if [ $((expected)) -ne "${after}" ]; then
  echo " Error: Wrong number of busybox2 entries in audit log."
  echo "        Expected $((expected - before)) more log entries. Expected ${expected}, found ${after}."
  exit "${FAIL:-1}"
fi

echo "INFO: Pass test 1"

# Test re-auditing using modified executable run in namespace

before="${after}"

echo "INFO: Testing re-auditing caused by executable in container"

policy="audit func=BPRM_CHECK mask=MAY_EXEC uid=0 "

SYNCFILE="syncfile" POLICY=${policy} \
  run_busybox_container_set_policy "/mnt" "${policy}" ./reaudit.sh
rc=$?
if [ ${rc} -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "${rc}"
fi

expected=$((before + 2 + num_extra))
after=$(wait_num_entries "${AUDITLOG}" "file=\"${rootfs}/bin/busybox2\"" $((expected)) 30)
if [ $((expected)) -ne "${after}" ]; then
  echo " Error: Wrong number of busybox2 entries in audit log."
  echo "        Expected $((expected - before)) more log entries. Expected ${expected}, found ${after}."
  exit "${FAIL:-1}"
fi

echo "INFO: Pass test 2"

exit "${SUCCESS:-0}"
