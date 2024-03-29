#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059

. ./ns-common.sh

KEY=./rsakey.pem
CERT=./rsa.crt

BUSYBOX2="$(which busybox2)"

SYNCFILE=${SYNCFILE:-syncfile}

mnt_securityfs "${SECURITYFS_MNT}"

# Wait until host has setup the policy now
if ! wait_file_gone "${SYNCFILE}" 50; then
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

set_appraisal_policy_from_string "${SECURITYFS_MNT}" "${appraisal_policy}" "" 0

POLICY="${POLICY}${appraisal_policy}"

nspolicy=$(${BUSYBOX2} cat "${SECURITYFS_MNT}/ima/policy")

if [ "$(printf "${POLICY}")" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: |$(printf "${POLICY}")|"
  echo "actual  : |${nspolicy}|"
  exit "${FAIL:-1}"
fi

# Expecting 1 measurement
ctr=$(grep -c "bin/busybox2" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find 1 measurement of busybox2 in container, found ${ctr}."
  exit "${FAIL:-1}"
fi

# Tell host to modify file now
echo > "${SYNCFILE}"

if ! wait_file_gone "${SYNCFILE}" 50; then
  echo " Error: Syncfile for indicating modified file did not disappear in time"
  exit "${FAIL:-1}"
fi

if ${BUSYBOX2} cat "${SECURITYFS_MNT}/ima/policy" 2>/dev/null 1>/dev/null; then
  echo " Error: Could execute ${BUSYBOX2} even though it should not be possible"
  exit "${FAIL:-1}"
fi

# Re-sign busybox2
evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${BUSYBOX2}" >/dev/null 2>&1

if ! ${BUSYBOX2} cat "${SECURITYFS_MNT}/ima/policy" 1>/dev/null; then
  echo " Error: Could not execute ${BUSYBOX2} even though it should be possible after re-signing"
  exit "${FAIL:-1}"
fi

# Expecting 2 or 3 measurements depending on template being used
template=$(get_template_from_log "${SECURITYFS_MNT}")
case "${template}" in
ima-sig|ima-ns) num_extra=1;;
*) num_extra=0;;
esac

ctr=$(grep -c "${BUSYBOX2}" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
exp=$((2 + num_extra))
if [ "${ctr}" -ne "${exp}" ]; then
  echo " Error: Could not find 2 measurement of busybox2 in container, found ${ctr}."
  exit "${FAIL:-1}"
fi

# Tell host to look at audit log now
echo > "${SYNCFILE}"

################### Part 2 ################

# Wait for host to indicated that it removed the signature
if ! wait_file_gone "${SYNCFILE}" 50; then
  echo " Error: Syncfile for indicating removed signature did not disappear in time"
  exit "${FAIL:-1}"
fi

if ${BUSYBOX2} cat "${SECURITYFS_MNT}/ima/policy" 2>/dev/null 1>/dev/null; then
  echo " Error: Could execute ${BUSYBOX2} even though it should not be possible after signature removal by host"
  exit "${FAIL:-1}"
fi

# Re-sign busybox2
evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${BUSYBOX2}" >/dev/null 2>&1

if ! ${BUSYBOX2} cat "${SECURITYFS_MNT}/ima/policy" 1>/dev/null; then
  echo " Error: Could not execute ${BUSYBOX2} even though it should be possible after re-signing"
  exit "${FAIL:-1}"
fi

# Tell host to look at audit log now
echo > "${SYNCFILE}"

exit "${SUCCESS:-0}"
