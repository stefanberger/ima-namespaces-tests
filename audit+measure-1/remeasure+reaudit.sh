#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059
SYNCFILE=${SYNCFILE:-syncfile}
POLICY=${POLICY:-}

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

# Wait until host has setup the policy now
if ! wait_file_gone "${SYNCFILE}" 50; then
  echo " Error: Syncfile did not disappear in time"
  exit "${FAIL:-1}"
fi

# Use busybox twice, once after modification
nspolicy=$(busybox2 cat "${SECURITYFS_MNT}/ima/policy")
echo >> "$(which busybox2)"
busybox2 cat "${SECURITYFS_MNT}/ima/policy" 1>/dev/null 2>/dev/null

# For this one no new measurement must be made and no new audit message must be sent:
busybox2 cat "${SECURITYFS_MNT}/ima/policy" 1>/dev/null 2>/dev/null

if [ "$(printf "${POLICY}")" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: |$(printf "${POLICY}")|"
  echo "actual  : |${nspolicy}|"
  exit "${FAIL:-1}"
fi

ctr=$(grep -c busybox2 "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 2 ]; then
  echo " Error: Could not find 2 measurements of busybox2 in container, found ${ctr}."
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
