#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059

. ./ns-common.sh

mnt_securityfs "/mnt"

KEY=./rsakey.pem
CERT=./rsa.crt

keyctl newring _ima @s >/dev/null 2>&1

# We want to see a measurement of the key when it gets loaded
prepolicy="measure func=KEY_CHECK \n"
printf "${prepolicy}" > /mnt/ima/policy || {
  echo " Error: Could not set key measurement policy. Does IMA-ns support IMA-measure?"
  exit "${SKIP:-3}"
}

keyctl padd asymmetric "" %keyring:_ima < "${CERT}" >/dev/null 2>&1

# Expecting measurement of key
ctr=$(grep -c " _ima " /mnt/ima/ascii_runtime_measurements)
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find measurement of key in container's measurement list."
  exit "${FAIL:-1}"
fi

# Sign evmctl to be able to use it later on
evmctl ima_sign --imasig --key "${KEY}" -a sha256 /usr/bin/evmctl >/dev/null 2>&1
if [ -z "$(getfattr -m ^security.ima -e hex --dump /usr/bin/evmctl 2>/dev/null)" ]; then
  echo " Error: security.ima should be there now. Is IMA appraisal support enabled?"
  # setting security.ima was only added when appraisal was enable
  exit "${SKIP:-3}"
fi

policy='appraise func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'\
'measure func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'

printf "${policy}" > /mnt/ima/policy || {
  echo " Error: Could not set appraise policy. Does IMA-ns support IMA-appraise?"
  exit "${SKIP:-3}"
}

# Using busybox2 must fail since it's not signed
if busybox2 cat /mnt/ima/policy >/dev/null 2>&1; then
   echo " Error: Could execute unsigned files even though appraise policy is active"
   exit "${FAIL:-1}"
fi

evmctl ima_sign --imasig --key "${KEY}" -a sha256 /bin/busybox2 >/dev/null 2>&1
evmctl ima_sign --imasig --key "${KEY}" -a sha256 /bin/busybox  >/dev/null 2>&1

template=$(get_template_from_log "/mnt")
[ "${template}" = "ima-sig" ] && num_extra=1 || num_extra=0

before=$(grep -c busybox2 /mnt/ima/ascii_runtime_measurements)

nspolicy=$(busybox2 cat /mnt/ima/policy)
policy="${prepolicy}${policy}"
if [ "$(printf "${policy}")" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: |$(printf "${policy}")|"
  echo "actual  : |${nspolicy}|"
  exit "${FAIL:-1}"
fi

after=$(grep -c busybox2 /mnt/ima/ascii_runtime_measurements)
expected=$((before + num_extra))
if [ "${expected}" -ne "${after}" ]; then
  echo " Error: Could not find ${expected} measurement of busybox2 in container, found ${after}."
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
