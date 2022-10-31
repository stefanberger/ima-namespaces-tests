#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059
#set -x

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

KEY=./rsakey.pem
CERT=./rsa.crt

# Start the child first before we cannot do that. Synchronize with child via
# $CMDFILE
SYNCFILE="${PWD}/syncfile"
TESTEXEC="${PWD}/bin/busybox2"
FAILFILE="${PWD}/failfile"
CMDFILE="${PWD}/cmdfile"

SUCCESS=${SUCCESS:-0} FAIL=${FAIL:-1} SKIP=${SKIP:-3} \
  PATH=${PATH} CMDFILE=${CMDFILE} TESTEXEC=${TESTEXEC} FAILFILE=${FAILFILE} SYNCFILE=${SYNCFILE} \
  unshare --user --map-root-user --mount --pid --fork ./child.sh &

# Prepare for appraisal policy activation

evmctl ima_sign --imasig --key "${KEY}" -a sha256 "$(which busybox)"  >/dev/null 2>&1
evmctl ima_sign --imasig --key "${KEY}" -a sha256 "$(which keyctl)"   >/dev/null 2>&1
evmctl ima_sign --imasig --key "${KEY}" -a sha256 "$(which evmctl)"   >/dev/null 2>&1
evmctl ima_sign --imasig --key "${KEY}" -a sha256 "$(which getfattr)" >/dev/null 2>&1
evmctl ima_sign --imasig --key "${KEY}" -a sha256 "$(which setfattr)" >/dev/null 2>&1

keyctl newring _ima @s >/dev/null 2>&1
keyctl padd asymmetric "" %keyring:_ima < "${CERT}" >/dev/null 2>&1

policy='measure func=KEY_CHECK \n'\
'appraise func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'\
'measure func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'
printf "${policy}" > "${SECURITYFS_MNT}/ima/policy" || {
  echo " Error: Could not set appraise policy. Does IMA-ns support IMA-appraisal?"
  exit "${SKIP:-3}"
}

if [ ! -f "${FAILFILE}" ]; then
  SYNCFILE="${PWD}/syncfile-1"
  wait_cage_full 0 "${SYNCFILE}" 2
fi

if [ ! -f "${FAILFILE}" ]; then
  printf "execute-fail" > "${CMDFILE}"
  open_cage "${SYNCFILE}"
  SYNCFILE="${PWD}/syncfile-2"
  wait_cage_full 0 "${SYNCFILE}" 2
fi

if [ ! -f "${FAILFILE}" ]; then
  # Sign file now; should now work in child container
  evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${TESTEXEC}" >/dev/null 2>&1
  printf "execute-success" > "${CMDFILE}"
  open_cage "${SYNCFILE}"
  SYNCFILE="${PWD}/syncfile-3"
  wait_cage_full 0 "${SYNCFILE}" 2
fi

if [ ! -f "${FAILFILE}" ]; then
  # Remove signature from file; Should nto work anymore in container
  setfattr -x security.ima "${TESTEXEC}"
  printf "execute-fail" > "${CMDFILE}"
  open_cage "${SYNCFILE}"
  SYNCFILE="${PWD}/syncfile-4"
  wait_cage_full 0 "${SYNCFILE}" 2
fi

printf "end" > "${CMDFILE}"
open_cage "${SYNCFILE}"

# Wait for child
wait

rc=$(cat "${FAILFILE}" 2>/dev/null)
if [ -n "${rc}" ]; then
  echo " Error: Child indicated failure code: ${rc}"
  exit "${rc}"
fi

exit "${SUCCESS:-0}"
