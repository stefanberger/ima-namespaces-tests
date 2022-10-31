#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

policy='measure func=BPRM_CHECK mask=MAY_EXEC uid=0 fowner=0'

echo "${policy}" > "${SECURITYFS_MNT}/ima/policy" || {
  echo " Error: Could not set measure policy. Does IMA-ns support IMA-measurement?"
  exit "${SKIP:-3}"
}

nspolicy=$(busybox2 cat "${SECURITYFS_MNT}/ima/policy")

if [ "${policy} " != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: ${policy}"
  echo "actual  : ${nspolicy}"
  exit "${FAIL:-1}"
fi

ctr=$(grep -c busybox2 "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find 1 measurement of busybox2 in container, found ${ctr}."
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
