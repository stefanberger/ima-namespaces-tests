#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059

. ./ns-common.sh

mnt_securityfs "/mnt"

policy='measure func=BPRM_CHECK mask=MAY_EXEC uid=0 template=ima-ng \n'\
'measure func=MMAP_CHECK mask=MAY_EXEC uid=0 template=ima-sig \n'

printf "${policy}" > /mnt/ima/policy || {
  echo " Error: Could not set appraise policy. Does IMA-ns support IMA-appraise?"
  exit "${SKIP:-3}"
}

# Exercise BPRM_CHECK and MMAP_CHECK
evmctl --help >/dev/null

libimaevm="$(find / 2>/dev/null| grep libimaevm)"

ctr=$(grep -c "${libimaevm} " /mnt/ima/ascii_runtime_measurements)
exp=1
if [ "${ctr}" -ne "${exp}" ]; then
  echo " Error: Expected ${exp} measurements of ${libimaevm} but found ${ctr}."
  exit "${FAIL:-1}"
fi

# Executables are only to be found with template 'ima-ng' and NOT ima-sig
for f in evmctl busybox; do
  fullpath="$(which "${f}")"

  # expect 0 log entries with ima-sig
  ctr=$(grep " ima-sig " /mnt/ima/ascii_runtime_measurements | grep -c "${fullpath}")
  if [ "${ctr}" -ne 0 ]; then
    echo " Error: ${f} should not have been logged with ima-sig."
    exit "${FAIL:-1}"
  fi

  # expect != 0 log entries with ima-ng
  ctr=$(grep " ima-ng " /mnt/ima/ascii_runtime_measurements | grep -c "${fullpath}")
  if [ "${ctr}" -eq 0 ]; then
    echo " Error: ${f} should have been logged with ima-ng."
    exit "${FAIL:-1}"
  fi
done

# Libraries are only to be found with template 'ima-sig'
ctr=$(grep " ima-sig " /mnt/ima/ascii_runtime_measurements | grep -c -E "\.so\.")
if [ "${ctr}" -eq 0 ]; then
  echo " Error: shared libraries should have been logged with template ima-sig."
  exit "${FAIL:-1}"
fi
ctr=$(grep " ima-ng " /mnt/ima/ascii_runtime_measurements | grep -c -E "\.so\.")
if [ "${ctr}" -ne 0 ]; then
  echo " Error: No shared libraries should have been logged with template ima-ng."
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
