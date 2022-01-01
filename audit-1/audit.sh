#!/bin/env sh

. ./ns-common.sh

mnt_securityfs "/mnt"

policy='audit func=BPRM_CHECK mask=MAY_EXEC uid=0 '

echo "${policy}" > /mnt/ima/policy || {
  echo " Error: Could not set audit policy."
  exit "${SKIP:-3}"
}

nspolicy=$(busybox2 cat /mnt/ima/policy)

if [ "${policy}" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: |${policy}|"
  echo "actual  : |${nspolicy}|"
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
