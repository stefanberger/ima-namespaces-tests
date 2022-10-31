#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059

#set -x

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

num_rules=0
rule="measure func=FILE_CHECK mask=MAY_READ \n"
policy=""

while [ "${num_rules}" -lt "${NUM_RULES_STEP}" ]; do
  policy="${policy}${rule}"
  num_rules=$((num_rules + 1))
done

old_ctr=0
while :; do
  # writing to policy will never fail since the kernel fs release operation
  # doesn't do anything with any error
  printf "${policy}" > "${SECURITYFS_MNT}/ima/policy"
  ctr=$(grep -c ^ "${SECURITYFS_MNT}/ima/policy")
  if [ "${ctr}" -gt "${LIMIT_RULES}" ]; then
    echo " Error: Number of rules in policy (${ctr}) exceed limit of ${LIMIT_RULES}"
    exit "${FAIL:-1}"
  fi
  # The normal case is where the rule count didn't change between writes
  if [ "${ctr}" -eq "${old_ctr}" ]; then
    break
  fi
  old_ctr="${ctr}"
done

exit "${SUCCESS:-0}"
