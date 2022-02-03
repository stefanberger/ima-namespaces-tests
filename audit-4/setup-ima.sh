#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# set -x

exp_policy="${2}"

. ./ns-common.sh

SYNCFILE=${SYNCFILE:-syncfile}  # make shellcheck happy

mnt_securityfs /mnt

echo > "${SYNCFILE}"

if ! wait_file_gone "${SYNCFILE}" 30; then
  echo " Error: Caller did not remove syncfile in time"
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

act_policy=$(cat /mnt/ima/policy)
if [ "${act_policy}" != "${exp_policy}" ]; then
  echo " Error: Expected policy different from actual one inside IMA namespace"
  echo " expected: ${exp_policy}"
  echo " actual  : ${act_policy}"
  echo >> "${FAILFILE}"
fi

echo > "${SYNCFILE}"

exit "${SUCCESS:-0}"
