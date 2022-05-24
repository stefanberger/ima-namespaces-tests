#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

. ./ns-common.sh

SYNCFILE=${SYNCFILE:-syncfile}

mnt_securityfs "/mnt"

# Wait until host has setup the policy now
if ! wait_file_gone "${SYNCFILE}" 50; then
  echo " Error: Syncfile did not disappear in time"
  exit "${FAIL:-1}"
fi

# Use busybox twice, once after modification
busybox2 cat /mnt/ima/policy 1>/dev/null 2>/dev/null
echo >> "$(which busybox2)"
busybox2 cat /mnt/ima/policy 1>/dev/null 2>/dev/null

# For this one no new audit message must be sent:
busybox2 cat /mnt/ima/policy 1>/dev/null 2>/dev/null

exit "${SUCCESS:-0}"
