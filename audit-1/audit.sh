#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause
POLICY=${POLICY:-}

. ./ns-common.sh

SYNCFILE=${SYNCFILE:-syncfile}

mnt_securityfs "${SECURITYFS_MNT}"

# Wait until host has setup the policy now
if ! wait_file_gone "${SYNCFILE}" 50; then
  echo " Error: Syncfile did not disappear in time"
  exit "${FAIL:-1}"
fi

nspolicy=$(busybox2 cat "${SECURITYFS_MNT}/ima/policy")

if [ "${POLICY}" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: |${POLICY}|"
  echo "actual  : |${nspolicy}|"
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
