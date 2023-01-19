#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

policy='measure func=BPRM_CHECK mask=MAY_EXEC uid=0 fowner=0 '

set_measurement_policy_from_string "${SECURITYFS_MNT}" "${policy}" ""

nspolicy=$(busybox2 cat "${SECURITYFS_MNT}/ima/policy")

ctr=$(grep -c busybox2 "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find 1 measurement of busybox2 in container, found ${ctr}."
  exit "${FAIL:-1}"
fi

exit_test "${SUCCESS:-0}"
