#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

#set -x

SYNCFILE=${SYNCFILE:-syncfile}  #make shellcheck happy

. ./ns-common.sh

mnt_securityfs /mnt

policy="audit func=BPRM_CHECK"
echo "${policy}" > /mnt/ima/policy 2>/dev/null && {
  echo " Error: Could set audit policy although this shouldn't be possible."
  exit "${FAIL:-1}"
}

exit "${SUCCESS:-0}"
