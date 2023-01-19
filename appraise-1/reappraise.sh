#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

KEY=./rsakey.pem
CERT=./rsa.crt

keyctl newring _ima @s >/dev/null 2>&1
keyctl padd asymmetric "" %keyring:_ima < "${CERT}" >/dev/null 2>&1
# Sign evmctl to be able to use it later on
evmctl ima_sign --imasig --key "${KEY}" -a sha256 /usr/bin/evmctl >/dev/null 2>&1

setfattr -x security.ima /bin/busybox2
if [ -n "$(getfattr -m ^security.ima -e hex --dump /bin/busybox2)" ]; then
  echo " Error: security.ima should be removed but it is still there"
  exit_test "${FAIL:-1}"
fi

policy='appraise func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'\
'measure func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'

printf "${policy}" > "${SECURITYFS_MNT}/ima/policy" || {
  echo " Error: Could not set appraise policy. Does IMA-ns support IMA-appraise?"
  exit_test "${SKIP:-3}"
}

# Using busybox2 must fail since it's not signed
if busybox2 cat "${SECURITYFS_MNT}/ima/policy" >/dev/null 2>&1; then
   echo " Error: Could execute unsigned file even though appraise policy is active"
   exit_test "${FAIL:-1}"
fi

evmctl ima_sign --imasig --key "${KEY}" -a sha256 /bin/busybox2 >/dev/null 2>&1
evmctl ima_sign --imasig --key "${KEY}" -a sha256 /bin/busybox  >/dev/null 2>&1

nspolicy=$(busybox2 cat "${SECURITYFS_MNT}/ima/policy")

if [ "$(printf "${policy}")" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: |$(printf "${policy}")|"
  echo "actual  : |${nspolicy}|"
  exit_test "${FAIL:-1}"
fi

# ima-sig gives us 2 entry already, ima-ng shows only 1
before=$(grep -c busybox2 "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")

# Modify file to invalidate signature
echo >> /bin/busybox2
# Using busybox2 must fail since it's not signed correctly anymore
if busybox2 cat "${SECURITYFS_MNT}/ima/policy" >/dev/null 2>&1; then
   echo " Error: Could execute badly signed file even though appraise policy is active"
   exit_test "${FAIL:-1}"
fi

evmctl ima_sign --imasig --key "${KEY}" -a sha256 /bin/busybox2 >/dev/null 2>&1
# Using busybox2 must work again now since signature is correct
if ! busybox2 cat "${SECURITYFS_MNT}/ima/policy" >/dev/null 2>&1; then
   echo " Error: Could NOT execute signed file after re-signing"
   exit_test "${FAIL:-1}"
fi

after=$(grep -c busybox2 "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "$((before * 2))" -ne "${after}" ]; then
  echo " Error: Could not find $((before * 2)) measurement(s) of busybox2 in container, found ${after}."
  exit_test "${FAIL:-1}"
fi

exit_test "${SUCCESS:-0}"
