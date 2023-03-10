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
	"${DIR}/measure+audit.sh" \
	"${DIR}/remeasure+reaudit.sh" \
	"${DIR}/tomtou.sh" \
	"${DIR}/open_writers.sh"

if ! check_ns_measure_support; then
  echo " Skip: IMA-ns does not support IMA-measure"
  exit "${SKIP:-3}"
fi

# Test auditing + measurements caused by executable run in namespace

# Accommodate the case where we have a host audit rule
num_extra=0
c1=$(grep -cE '^audit.*func=BPRM_CHECK .*mask=MAY_EXEC.*' "${SECURITYFS_MNT}/ima/policy")
c2=$(grep -E '^audit.*func=BPRM_CHECK ' "${SECURITYFS_MNT}/ima/policy" |
       grep -cv " mask=")
[ "$((c1+c2))" -ne 0 ] && num_extra=1

rootfs=$(get_busybox_container_root)
before=$(grep -c "file=\"${rootfs}/bin/busybox2\"" "${AUDITLOG}")

echo "INFO: Testing auditing and measurements inside container"

policy='measure func=BPRM_CHECK mask=MAY_EXEC uid=0 fowner=0 \n'\
'audit func=BPRM_CHECK mask=MAY_EXEC uid=0 fowner=0 \n'

SYNCFILE="syncfile" POLICY="${policy}" \
  run_busybox_container_set_policy "/mnt" "${policy}" ./measure+audit.sh
rc=$?
if [ $rc -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "$rc"
fi

expected=$((before + 1 + num_extra))
after=$(wait_num_entries "${AUDITLOG}" "file=\"${rootfs}/bin/busybox2\"" "${expected}" 30)
if [ "${expected}" -ne "${after}" ]; then
  echo " Error: Wrong number of busybox2 entries in audit log."
  echo "        Expected $((expected - before)) more log entries. Expected ${expected}, found ${after}."
  exit "${FAIL:-1}"
fi

echo "INFO: Pass test 1"

# Test re-auditing and re-measuring using modified executable run in namespace

before="${after}"

echo "INFO: Testing re-auditing and re-measurement caused by executable in container"

policy='measure func=BPRM_CHECK mask=MAY_EXEC uid=0 fowner=0 \n'\
'audit func=BPRM_CHECK mask=MAY_EXEC uid=0 fowner=0 \n'

SYNCFILE="syncfile" POLICY=${policy} \
  run_busybox_container_set_policy "/mnt" "${policy}" ./remeasure+reaudit.sh
rc=$?
if [ ${rc} -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "${rc}"
fi

expected=$((before + 2 + num_extra))
after=$(wait_num_entries "${AUDITLOG}" "file=\"${rootfs}/bin/busybox2\"" "${expected}" 30)
if [ "${expected}" -ne "${after}" ]; then
  echo " Error: Wrong number of busybox2 entries in audit log."
  echo "        Expected $((expected - before)) more log entries. Expected ${expected}, found ${after}."
  exit "${FAIL:-1}"
fi

echo "INFO: Pass test 2"

# Cause a TomToU violation from within the container that MUST NOT be audited

search=" cause=ToMToU .* name=\"${rootfs}/testfile\""
before=$(grep -c "${search}" "${AUDITLOG}")

echo "INFO: Testing that TomToU violation inside container is NOT audited"

policy='audit func=FILE_CHECK mask=MAY_READ uid=0 fowner=0 \n'\
'measure func=FILE_CHECK mask=MAY_READ uid=0 fowner=0 \n'

# Number of ToMToU audit log entries is influenced by measure rules on the host
num_extra_measure=0
ctr=$(grep -c -E '^measure.*func=FILE_CHECK .*MAY_READ' "${SECURITYFS_MNT}/ima/policy")
[ "${ctr}" -ne 0 ] && num_extra_measure=1

SYNCFILE="syncfile" POLICY=${policy} \
  run_busybox_container_set_policy "/mnt" "${policy}" ./tomtou.sh
rc=$?
if [ ${rc} -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "${rc}"
fi

expected=$((before + num_extra_measure))
after=$(wait_num_entries "${AUDITLOG}" "${search}" "${expected}" 30)
if [ "${expected}" -ne "${after}" ]; then
  echo " Error: Wrong number of '${search}' entries in audit log."
  echo "        Expected $((expected - before)) more log entries. Expected ${expected}, found ${after}."
  exit "${FAIL:-1}"
fi

echo "INFO: Pass test 3"
# Cause a open_writers violation in the container

search=" cause=open_writers .* name=\"${rootfs}/testfile\""
before=$(grep -c "${search}" "${AUDITLOG}")

echo "INFO: Testing that open_writers violation inside container is NOT audited"

policy='audit func=FILE_CHECK mask=MAY_READ uid=0 fowner=0 \n'\
'measure func=FILE_CHECK mask=MAY_READ uid=0 fowner=0 \n'

SYNCFILE="syncfile" POLICY=${policy} \
  run_busybox_container_set_policy "/mnt" "${policy}" ./open_writers.sh
rc=$?
if [ ${rc} -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "${rc}"
fi

# The host will emit an audit message if there's a measuring rule
# https://elixir.bootlin.com/linux/v5.16.5/source/security/integrity/ima/ima_main.c#L138
expected=$((before + num_extra_measure))
after=$(wait_num_entries "${AUDITLOG}" "${search}" "${expected}" 30)
if [ "${expected}" -ne "${after}" ]; then
  echo " Error: Wrong number of '${search}' entries in audit log."
  echo "        Expected $((expected - before)) more log entries. Expected ${expected}, found ${after}."
  exit "${FAIL:-1}"
fi

echo "INFO: Pass test 4"

exit "${SUCCESS:-0}"
