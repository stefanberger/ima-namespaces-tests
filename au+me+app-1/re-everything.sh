#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059

. ./ns-common.sh

KEY=./rsakey.pem
CERT=./rsa.crt

BUSYBOX2="$(which busybox2)"

SYNCFILE=${SYNCFILE:-syncfile}

mnt_securityfs "/mnt"

# Wait until host has setup the policy now
if ! wait_file_gone "${SYNCFILE}" 20; then
  echo " Error: Syncfile did not disappear in time"
  exit "${FAIL:-1}"
fi

# Sign applications before activating appraisal policy
keyctl newring _ima @s >/dev/null 2>&1
keyctl padd asymmetric "" %keyring:_ima < "${CERT}" >/dev/null 2>&1

evmctl ima_sign --imasig --key "${KEY}" -a sha256 "$(which evmctl)"  >/dev/null 2>&1
evmctl ima_sign --imasig --key "${KEY}" -a sha256 "$(which keyctl)"  >/dev/null 2>&1
evmctl ima_sign --imasig --key "${KEY}" -a sha256 "$(which busybox)" >/dev/null 2>&1
evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${BUSYBOX2}"      >/dev/null 2>&1

# now add appraisal policy rule
appraisal_policy="appraise func=BPRM_CHECK mask=MAY_EXEC uid=0 \n"
if ! printf "${appraisal_policy}" > /mnt/ima/policy; then
  echo " Error: Could not set appraisal policy in namespace"
  exit "${SKIP:-3}"
fi
POLICY="${POLICY}${appraisal_policy}"

nspolicy=$(${BUSYBOX2} cat /mnt/ima/policy)

if [ "$(printf "${POLICY}")" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: |$(printf "${POLICY}")|"
  echo "actual  : |${nspolicy}|"
  exit "${FAIL:-1}"
fi

# Expecting 1 measurement
ctr=$(grep -c "bin/busybox2" /mnt/ima/ascii_runtime_measurements)
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find 1 measurement of busybox2 in container, found ${ctr}."
  exit "${FAIL:-1}"
fi

# Tell host to modify file now
echo > "${SYNCFILE}"

if ! wait_file_gone "${SYNCFILE}" 20; then
  echo " Error: Syncfile for indicating modified file did not disappear in time"
  exit "${FAIL:-1}"
fi

if ${BUSYBOX2} cat /mnt/ima/policy 2>/dev/null 1>/dev/null; then
  echo " Error: Could execute ${BUSYBOX2} even though it should not be possible"
  exit "${FAIL:-1}"
fi

# Re-sign busybox2
evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${BUSYBOX2}" >/dev/null 2>&1

if ! ${BUSYBOX2} cat /mnt/ima/policy 1>/dev/null; then
  echo " Error: Could not execute ${BUSYBOX2} even though it should be possible after re-signing"
  exit "${FAIL:-1}"
fi

# Expecting 2 measurements
ctr=$(grep -c "${BUSYBOX2}" /mnt/ima/ascii_runtime_measurements)
if [ "${ctr}" -ne 2 ]; then
  echo " Error: Could not find 2 measurement of busybox2 in container, found ${ctr}."
  exit "${FAIL:-1}"
fi

# Tell host to look at audit log now
echo > "${SYNCFILE}"

################### Part 2 ################

# Wait for host to indicated that it removed the signature
if ! wait_file_gone "${SYNCFILE}" 20; then
  echo " Error: Syncfile for indicating removed signature did not disappear in time"
  exit "${FAIL:-1}"
fi

if ${BUSYBOX2} cat /mnt/ima/policy 2>/dev/null 1>/dev/null; then
  echo " Error: Could execute ${BUSYBOX2} even though it should not be possible after signature removal by host"
  exit "${FAIL:-1}"
fi

# Re-sign busybox2
evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${BUSYBOX2}" >/dev/null 2>&1

if ! ${BUSYBOX2} cat /mnt/ima/policy 1>/dev/null; then
  echo " Error: Could not execute ${BUSYBOX2} even though it should be possible after re-signing"
  exit "${FAIL:-1}"
fi

# Tell host to look at audit log now
echo > "${SYNCFILE}"

exit "${SUCCESS:-0}"
