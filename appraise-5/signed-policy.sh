#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059
# set -x

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

KEY=./rsakey.pem
CERT=./rsa.crt

keyctl newring _ima @s >/dev/null 2>&1
keyctl padd asymmetric "" %keyring:_ima < "${CERT}" >/dev/null 2>&1

prepolicy='dont_appraise fsmagic=0x73636673 \n'\
'appraise func=POLICY_CHECK mask=MAY_READ \n'

set_appraisal_policy_from_string "${SECURITYFS_MNT}" "${prepolicy}" "" 1

policy='appraise func=POLICY_CHECK mask=MAY_READ uid=0 \n'
printf "${policy}" > /policyfile

echo "/policyfile" > "${SECURITYFS_MNT}/ima/policy" 2>/dev/null && {
  echo " Error: Could set unsigned policy"
  exit_test "${FAIL:-1}"
}

if ! msg=$(evmctl ima_sign --imasig --key "${KEY}" -a sha256 "/policyfile" 2>&1); then
  echo " Error: evmctl failed: ${msg}"
  exit_test "${FAIL:-1}"
fi

echo "/policyfile" > "${SECURITYFS_MNT}/ima/policy" 2>/dev/null || {
  echo " Error: Could not set signed policy"
  exit_test "${FAIL:-1}"
}

# try initial policy again
printf "${prepolicy}" > "${SECURITYFS_MNT}/ima/policy" && {
  echo " Error: Could set policy by writing policy rules even though this should not work"
  exit_test "${SKIP:-3}"
}

nspolicy=$(cat "${SECURITYFS_MNT}/ima/policy")
expected=$(printf "${prepolicy}${policy}")
if [ "${nspolicy}" != "${expected}" ]; then
  echo " Error: Wrong policy in namespace"
  echo "expected: |${expected}|"
  echo "actual  : |${nspolicy}|"
  exit_test "${FAIL:-1}"
fi

exit_test "${SUCCESS:-0}"
