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
	"${DIR}/measure+audit.sh" \
	"${DIR}/remeasure+reaudit.sh" \
	"${DIR}/tomtou.sh" \
	"${DIR}/open_writers.sh"

# Test auditing + measurements caused by executable run in namespace

# Accomodate the case where we have a host audit rule
num_extra=0
ctr=$(grep -c -E '^audit.*func=BPRM_CHECK .*MAY_EXEC' /sys/kernel/security/ima/policy)
[ "${ctr}" -ne 0 ] && num_extra=1

before=$(grep -c "rootfs/bin/busybox2" "${AUDITLOG}")

echo "INFO: Testing auditing and measurements inside container"

run_busybox_container ./measure+audit.sh
rc=$?
if [ $rc -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "$rc"
fi

expected=$((before + 1 + num_extra))
after=$(wait_num_entries "${AUDITLOG}" "rootfs/bin/busybox2" "${expected}" 30)
if [ "${expected}" -ne "${after}" ]; then
  echo " Error: Wrong number of busybox2 entries in audit log."
  echo "        Expected ${expected}, found ${after}."
  exit "${FAIL:-1}"
fi

echo "INFO: Pass test 1"

# Test re-auditing and re-measuring using modified executable run in namespace

before="${after}"

echo "INFO: Testing re-auditing and re-measurement caused by executable in container"

run_busybox_container ./remeasure+reaudit.sh
rc=$?
if [ ${rc} -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "${rc}"
fi

expected=$((before + 2 + num_extra))
after=$(wait_num_entries "${AUDITLOG}" "rootfs/bin/busybox2" "${expected}" 30)
if [ "${expected}" -ne "${after}" ]; then
  echo " Error: Wrong number of busybox2 entries in audit log."
  echo "        Expected ${expected}, found ${after}."
  exit "${FAIL:-1}"
fi

echo "INFO: Pass test 2"

# Cause a TomToU violation in the container

search=" cause=ToMToU .*rootfs/testfile"
before=$(grep -c "${search}" "${AUDITLOG}")

echo "INFO: Testing TomToU violation inside container"

run_busybox_container ./tomtou.sh
rc=$?
if [ ${rc} -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "${rc}"
fi

expected=$((before + 2 + num_extra))
after=$(wait_num_entries "${AUDITLOG}" "${search}" "${expected}" 30)
if [ "${expected}" -ne "${after}" ]; then
  echo " Error: Wrong number of '${search}' entries in audit log."
  echo "        Expected ${expected}, found ${after}."
  exit "${FAIL:-1}"
fi

echo "INFO: Pass test 3"

# Cause a open_writers violation in the container

search=" cause=open_writers .*rootfs/testfile"
before=$(grep -c "${search}" "${AUDITLOG}")

echo "INFO: Testing open_writers violation inside container"

run_busybox_container ./open_writers.sh
rc=$?
if [ ${rc} -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "${rc}"
fi

expected=$((before + 1))
after=$(wait_num_entries "${AUDITLOG}" "${search}" "${expected}" 30)
if [ "${expected}" -ne "${after}" ]; then
  echo " Error: Wrong number of '${search}' entries in audit log."
  echo "        Expected ${expected}, found ${after}."
  exit "${FAIL:-1}"
fi

echo "INFO: Pass test 4"

exit "${SUCCESS:-0}"
