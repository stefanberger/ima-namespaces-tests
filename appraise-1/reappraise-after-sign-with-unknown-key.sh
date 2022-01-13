#!/bin/env sh

# shellcheck disable=SC2059

. ./ns-common.sh

mnt_securityfs "/mnt"

KEY=./rsakey.pem
CERT=./rsa.crt
# Key used for signing but cert not known to IMA
KEY2=./rsakey2.pem

keyctl newring _ima @s >/dev/null 2>&1
keyctl padd asymmetric "" %keyring:_ima < "${CERT}" >/dev/null 2>&1
# Sign evmctl to be able to use it later on
evmctl ima_sign --imasig --key "${KEY}" -a sha256 /usr/bin/evmctl >/dev/null 2>&1

setfattr -x security.ima /bin/busybox2
if [ -n "$(getfattr -m ^security.ima -e hex --dump /bin/busybox2)" ]; then
  echo " Error: security.ima should be removed but it is still there"
  exit "${FAIL:-1}"
fi

policy='appraise func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'\
'measure func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'

printf "${policy}" > /mnt/ima/policy || {
  echo " Error: Could not set appraise policy. Does IMA-ns support IMA-appraise?"
  exit "${SKIP:-3}"
}

# Using busybox2 must fail since it's not signed
if busybox2 cat /mnt/ima/policy >/dev/null 2>&1; then
   echo " Error: Could execute unsigned file even though appraise policy is active"
   exit "${FAIL:-1}"
fi

evmctl ima_sign --imasig --key "${KEY}" -a sha256 /bin/busybox2 >/dev/null 2>&1
evmctl ima_sign --imasig --key "${KEY}" -a sha256 /bin/busybox  >/dev/null 2>&1

nspolicy=$(busybox2 cat /mnt/ima/policy)

if [ "$(printf "${policy}")" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: |$(printf "${policy}")|"
  echo "actual  : |${nspolicy}|"
  exit "${FAIL:-1}"
fi

# ima-sig gives us 2 entry already, ima-ng shows only 1
before=$(grep -c busybox2 /mnt/ima/ascii_runtime_measurements)

# Sign busybox2 with key unknown to IMA
evmctl ima_sign --imasig --key "${KEY2}" -a sha256 /bin/busybox2 >/dev/null 2>&1
# Using busybox2 must fail since it's not signed correctly anymore
if busybox2 cat /mnt/ima/policy >/dev/null 2>&1; then
   echo " Error: Could execute badly signed file even though appraise policy is active"
   exit "${FAIL:-1}"
fi

evmctl ima_sign --imasig --key "${KEY}" -a sha256 /bin/busybox2 >/dev/null 2>&1
# Using busybox2 must work again now since signature is correct
if ! busybox2 cat /mnt/ima/policy >/dev/null 2>&1; then
   echo " Error: Could NOT execute signed file after re-signing"
   exit "${FAIL:-1}"
fi

after=$(grep -c busybox2 /mnt/ima/ascii_runtime_measurements)
if [ "$((before * 2 - 1))" -ne "${after}" ]; then
  echo " Error: Could not find $((before * 2 - 1)) measurement(s) of busybox2 in container, found ${after}."
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
