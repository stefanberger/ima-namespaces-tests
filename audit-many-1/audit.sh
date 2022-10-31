#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059

# Caller must pass:
# NSID: distinct namespace id number
# FAILFILE: name of file to create upon failure
SYNCFILE=${SYNCFILE:-syncfile}
FAILFILE=${FAILFILE:-failfile}

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

# Wait until host has setup the policy now
if ! wait_file_gone "${SYNCFILE}" 50; then
  echo " Error: Syncfile did not disappear in time"
  exit "${FAIL:-1}"
fi

policy='audit func=BPRM_CHECK mask=MAY_EXEC uid=0 '

nspolicy=$(busybox2 cat "${SECURITYFS_MNT}/ima/policy")

if [ "${policy}" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: ${policy}"
  echo "actual  : ${nspolicy}"
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
