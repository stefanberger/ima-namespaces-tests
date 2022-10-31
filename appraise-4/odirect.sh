#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059
# set -x

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

KEY=./rsakey.pem
CERT=./rsa.crt

dd=$(which dd)  # never use busybox's dd

keyctl newring _ima @s >/dev/null 2>&1
keyctl padd asymmetric "" %keyring:_ima < "${CERT}" >/dev/null 2>&1

# Input file for copying
echo 12345 > inputfile

# Sign libs and tools to be able to use it later on
for tgt in \
    inputfile \
    $(find ./ 2>/dev/null | grep -E "\.so") \
    "${dd}" \
    $(which evmctl); do
  if ! msg=$(evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${tgt}" 2>&1); then
    echo " Error: evmctl failed: ${msg}"
    exit "${FAIL:-1}"
  fi
done

policy='dont_appraise fsmagic=0x73636673 \n'\
'appraise func=FILE_CHECK mask=MAY_READ uid=0 \n'

printf "${policy}" > "${SECURITYFS_MNT}/ima/policy" || {
  echo " Error: Could not set appraise policy. Does IMA-ns support IMA-appraise?"
  exit "${SKIP:-3}"
}

# Using dd with flag O_DIRECT must fail since it's not allowed with directio
if "${dd}" if=inputfile iflag=direct of=outputfile oflag=direct status=none 2>/dev/null; then
   echo " Error: Could run dd with O_DIRECTIO even though it shouldn't be allowed"
   exit "${FAIL:-1}"
fi

# Using dd with flag O_DIRECT must fail since it's not allowed with directio
if ! "${dd}" if=inputfile of=outputfile status=none; then
   echo " Error: Could NOT run dd even though it should work"
   exit "${FAIL:-1}"
fi
rm -f outputfile

policyadd='appraise func=FILE_CHECK mask=MAY_READ uid=0 permit_directio \n'
printf "${policyadd}" > "${SECURITYFS_MNT}/ima/policy" || {
  echo " Error: Could not set appraise policy. Does IMA-ns support IMA-appraise?"
  exit "${SKIP:-3}"
}

# Using dd with flag O_DIRECT must work now since policy allows O_DIRECTIO
if ! "${dd}" if=inputfile iflag=direct of=outputfile oflag=direct status=none; then
   echo " Error: Could NOT run dd with O_DIRECTIO even though it shouldn't be allowed"
   exit "${FAIL:-1}"
fi

nspolicy=$(busybox2 cat "${SECURITYFS_MNT}/ima/policy")
policy="${policy}${policyadd}"
if [ "$(printf "${policy}")" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: |$(printf "${policy}")|"
  echo "actual  : |${nspolicy}|"
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
