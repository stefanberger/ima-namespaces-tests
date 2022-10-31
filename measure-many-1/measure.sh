#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059

# Caller must pass:
# NSID: distinct namespace id number
# FAILFILE: name of file to create upon failure

FAILFILE=${FAILFILE:-failfile}

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

policy='measure func=BPRM_CHECK mask=MAY_EXEC uid=0 '

set_measurement_policy_from_string "${SECURITYFS_MNT}" "${policy}" "${FAILFILE}"

nspolicy=$(busybox2 cat "${SECURITYFS_MNT}/ima/policy")

ctr=$(grep -c busybox2 "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find 1 measurement of busybox2 in container, found ${ctr}."
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
