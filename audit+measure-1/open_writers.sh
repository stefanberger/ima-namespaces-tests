#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3023

. ./ns-common.sh

mnt_securityfs "/mnt"

echo "testtest" > testfile

policy='audit func=FILE_CHECK mask=MAY_READ uid=0 \n'\
'measure func=FILE_CHECK mask=MAY_READ uid=0 \n'

printf "${policy}" > /mnt/ima/policy || {
  echo " Error: Could not set audit+measure policy."
  exit "${SKIP:-3}"
}

nspolicy=$(cat /mnt/ima/policy)

if [ "$(printf "${policy}")" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: |$(printf "${policy}")|"
  echo "actual  : |${nspolicy}|"
  exit "${FAIL:-1}"
fi


exec 101>testfile
exec 100<testfile
exec 100>&-
exec 101>&-

# expecting an entry like this:
#10 0000000000000000000000000000000000000000 ima-ng sha1:0000000000000000000000000000000000000000 /run/imatest/rootfs/testfile
ctr=$(grep -c -E '^10 [0]{40} .* sha1:[0]{40} .*rootfs/testfile' /mnt/ima/ascii_runtime_measurements)
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find 1 entry for violation in container, found ${ctr}."
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
