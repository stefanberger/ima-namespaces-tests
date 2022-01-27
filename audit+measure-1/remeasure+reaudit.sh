#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059

. ./ns-common.sh

mnt_securityfs "/mnt"

policy='measure func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'\
'audit func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'

printf "${policy}" > /mnt/ima/policy || {
  echo " Error: Could not set measure+audit policy."
  exit "${SKIP:-3}"
}

# Use busybox twice, once after modification
nspolicy=$(busybox2 cat /mnt/ima/policy)
echo >> "$(which busybox2)"
busybox2 cat /mnt/ima/policy 1>/dev/null 2>/dev/null

# For this one no new measurement must be made and no new audit message must be sent:
busybox2 cat /mnt/ima/policy 1>/dev/null 2>/dev/null

if [ "$(printf "${policy}")" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: |$(printf "${policy}")|"
  echo "actual  : |${nspolicy}|"
  exit "${FAIL:-1}"
fi

ctr=$(grep -c busybox2 /mnt/ima/ascii_runtime_measurements)
if [ "${ctr}" -ne 2 ]; then
  echo " Error: Could not find 2 measurements of busybox2 in container, found ${ctr}."
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
