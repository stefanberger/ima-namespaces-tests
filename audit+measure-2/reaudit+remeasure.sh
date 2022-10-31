#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059
SYNCFILE=${SYNCFILE:-syncfile}
FAILFILE=${FAILFILE:-failfile}
POLICY=${POLICY:-}

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

# Wait until host has setup the policy now
if ! wait_file_gone "${SYNCFILE}" 50; then
  echo " Error: Syncfile did not disappear in time"
  exit "${FAIL:-1}"
fi

nspolicy=$(busybox2 cat "${SECURITYFS_MNT}/ima/policy")

if [ "$(printf "${POLICY}")" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: |${POLICY}|"
  echo "actual  : |${nspolicy}|"
  exit "${FAIL:-1}"
fi

# Expecting 1 measurement
ctr=$(grep -c "bin/busybox2" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find 1 measurement of busybox2 in container, found ${ctr}."
  exit "${FAIL:-1}"
fi

# Tell host to modify file now
echo > "${SYNCFILE}"

if ! wait_file_gone "${SYNCFILE}" 50; then
  echo " Error: Syncfile for indicating modified file did not disappear in time"
  exit "${FAIL:-1}"
fi

busybox2 cat "${SECURITYFS_MNT}/ima/policy" 1>/dev/null

# Expecting 2 measurements
ctr=$(grep -c "bin/busybox2" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 2 ]; then
  echo " Error: Could not find 2 measurement of busybox2 in container, found ${ctr}."
  exit "${FAIL:-1}"
fi

# Tell host to look at audit log now
echo > "${SYNCFILE}"

exit "${SUCCESS:-0}"
