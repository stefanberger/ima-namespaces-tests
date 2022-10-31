#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059

. ./ns-common.sh

SYNCFILE=${SYNCFILE:-syncfile}

mnt_securityfs "${SECURITYFS_MNT}"

# Wait until host has setup the policy now
if ! wait_file_gone "${SYNCFILE}" 50; then
  echo " Error: Syncfile did not disappear in time"
  exit "${FAIL:-1}"
fi

nspolicy=$(busybox2 cat "${SECURITYFS_MNT}/ima/policy")

if [ "$(printf "${POLICY}")" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: |$(printf "${POLICY}")|"
  echo "actual  : |${nspolicy}|"
  exit "${FAIL:-1}"
fi

ctr=$(grep -c busybox2 "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find 1 measurement of busybox2 in container, found ${ctr}."
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
