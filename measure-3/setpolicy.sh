#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

#set -x

SYNCFILE=${SYNCFILE:-syncfile}  #make shellcheck happy
FAILFILE=${FAILFILE:-failfile}

. ./ns-common.sh

mnt_securityfs /mnt

policy="measure func=BPRM_CHECK uid=0 gid=0"
echo "${policy}" > /mnt/ima/policy || {
  echo " Error: Could not set measure policy."
  echo > "${FAILFILE}"
}

echo > "${SYNCFILE}"

sleep 3
