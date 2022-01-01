#!/bin/env sh

. ./ns-common.sh

mnt_securityfs "/mnt"

policy='audit func=BPRM_CHECK mask=MAY_EXEC uid=0'

echo "${policy}" > /mnt/ima/policy || {
  echo " Error: Could not set audit policy."
  exit "${SKIP:-3}"
}

# Use busybox twice, once after modification
busybox2 cat /mnt/ima/policy 1>/dev/null 2>/dev/null
echo >> "$(which busybox2)"
busybox2 cat /mnt/ima/policy 1>/dev/null 2>/dev/null

# For this one no new audit message must be sent:
busybox2 cat /mnt/ima/policy 1>/dev/null 2>/dev/null

exit "${SUCCESS:-0}"
