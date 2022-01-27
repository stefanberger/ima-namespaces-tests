#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059
# set -x

. ./ns-common.sh

mnt_securityfs "/mnt"

KEY=./rsakey.pem
CERT=./rsa.crt

keyctl newring _ima @s >/dev/null 2>&1
keyctl padd asymmetric "" %keyring:_ima < "${CERT}" >/dev/null 2>&1

prepolicy='dont_appraise fsmagic=0x73636673 \n'\
'appraise func=POLICY_CHECK mask=MAY_READ \n'

printf "${prepolicy}" > /mnt/ima/policy || {
  echo " Error: Could not set policy appraise policy. Does IMA-ns support IMA-appraise?"
  exit "${SKIP:-3}"
}

policy='appraise func=FILE_CHECK mask=MAY_READ uid=0 \n'
printf "${policy}" > /policyfile

echo "/policyfile" > /mnt/ima/policy 2>/dev/null && {
  echo " Error: Could set unsigned policy"
  exit "${FAIL:-1}"
}

if ! msg=$(evmctl ima_sign --imasig --key "${KEY}" -a sha256 "/policyfile" 2>&1); then
  echo " Error: evmctl failed: ${msg}"
  exit "${FAIL:-1}"
fi

echo "/policyfile" > /mnt/ima/policy 2>/dev/null || {
  echo " Error: Could not set signed policy"
  exit "${FAIL:-1}"
}

# try initial policy again
printf "${prepolicy}" > /mnt/ima/policy && {
  echo " Error: Could set policy by writing policy rules even though this should not work"
  exit "${SKIP:-3}"
}

nspolicy=$(cat /mnt/ima/policy)
expected=$(printf "${prepolicy}${policy}")
if [ "${nspolicy}" != "${expected}" ]; then
  echo " Error: Wrong policy in namespace"
  echo "expected: |${expected}|"
  echo "actual  : |${nspolicy}|"
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
