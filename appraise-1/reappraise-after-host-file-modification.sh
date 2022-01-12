#!/bin/env sh
#set -x

# shellcheck disable=SC2059

# Calling script needs to set the following variables:
# SYNCFILE: path to the syncfile that this script needs to create
# TESTEXE:  path to the test executable, e.g., bin/busybox2

. ./ns-common.sh

mnt_securityfs "/mnt"

KEY=./rsakey.pem
CERT=./rsa.crt

keyctl newring _ima @s >/dev/null 2>&1
keyctl padd asymmetric "" %keyring:_ima < "${CERT}" >/dev/null 2>&1
# Sign evmctl to be able to use it later on
evmctl ima_sign --imasig --key "${KEY}" -a sha256 /usr/bin/evmctl >/dev/null 2>&1

setfattr -x security.ima "${TESTEXE}"
if [ -n "$(getfattr -m ^security.ima -e hex --dump "${TESTEXE}")" ]; then
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
if "${TESTEXE}" cat /mnt/ima/policy >/dev/null 2>&1; then
   echo " Error: Could execute unsigned file even though appraise policy is active"
   exit "${FAIL:-1}"
fi

evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${TESTEXE}"  >/dev/null 2>&1
evmctl ima_sign --imasig --key "${KEY}" -a sha256 /bin/busybox  >/dev/null 2>&1

nspolicy=$("${TESTEXE}" cat /mnt/ima/policy)

if [ "$(printf "${policy}")" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: |$(printf "${policy}")|"
  echo "actual  : |${nspolicy}|"
  exit "${FAIL:-1}"
fi

# ima-sig gives us 2 entry already, ima-ng shows only 1
before=$(grep -c busybox2 /mnt/ima/ascii_runtime_measurements)

# Let the host script know that it should modify the file now
echo > "${SYNCFILE}"

# Host script lets us know when it modified the file
ctr=0
while [ -f "${SYNCFILE}" ]; do
  ctr=$((ctr + 1))
  if [ "$ctr" -eq 40 ]; then
    echo " Error: Test script did not remove syncfile!"
    exit "${FAIL:-1}"
  fi
  sleep 0.1
done

# Using busybox2 must fail since it's not signed correctly anymore
if "${TESTEXE}" cat /mnt/ima/policy >/dev/null 2>&1; then
   echo " Error: Could execute badly signed file even though appraise policy is active"
   exit "${FAIL:-1}"
fi

evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${TESTEXE}" >/dev/null 2>&1
# Using busybox2 must work now since it's properly signed again
if ! "${TESTEXE}" cat /mnt/ima/policy >/dev/null 2>&1; then
   echo " Error: Could NOT execute signed file after re-signing"
   exit "${FAIL:-1}"
fi

after=$(grep -c "${TESTEXE}" /mnt/ima/ascii_runtime_measurements)
if [ "$((before * 2))" -ne "${after}" ]; then
  echo " Error: Could not find $((before * 2)) measurement(s) of ${TESTEXE} in container, found ${after}."
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
