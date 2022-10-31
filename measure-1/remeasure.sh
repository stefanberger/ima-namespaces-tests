#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

policy='measure func=BPRM_CHECK mask=MAY_EXEC uid=0'

echo "${policy}" > "${SECURITYFS_MNT}/ima/policy" || {
  echo " Error: Could not set audit policy."
  exit "${SKIP:-3}"
}

# Use busybox twice, once after modification
busybox2 cat "${SECURITYFS_MNT}/ima/policy" 1>/dev/null 2>/dev/null
ctr=$(grep -c busybox2 "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find 1 measurement of busybox2 in container, found ${ctr}."
  exit "${FAIL:-1}"
fi

echo >> "$(which busybox2)"

# test re-measuring twice; one more measurement is expected
loop=0
while [ "$loop" -le 1 ]; do
  busybox2 cat "${SECURITYFS_MNT}/ima/policy" 1>/dev/null 2>/dev/null
  ctr="$(grep -c busybox2 "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")"
  if [ "${ctr}" -ne 2 ]; then
    echo " Error: Could not find 2 measurements of busybox2 in container, found ${ctr}."
    exit "${FAIL:-1}"
  fi
  loop=$((loop+1))
done

exit "${SUCCESS:-0}"
