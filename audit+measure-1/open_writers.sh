#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3023
SYNCFILE=${SYNCFILE:-syncfile}
POLICY=${POLICY:-}

. ./ns-common.sh

imahash="sha1"
imatemplate="ima-ng"
hashlen=$(($(get_hash_length "${imahash}") * 2))
mnt_securityfs "${SECURITYFS_MNT}" "${imahash}" "${imatemplate}"

echo "testtest" > testfile

# Wait until host has setup the policy now
if ! wait_file_gone "${SYNCFILE}" 50; then
  echo " Error: Syncfile did not disappear in time"
  exit "${FAIL:-1}"
fi

nspolicy=$(cat "${SECURITYFS_MNT}/ima/policy")

if [ "$(printf "${POLICY}")" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: |$(printf "${POLICY}")|"
  echo "actual  : |${nspolicy}|"
  exit "${FAIL:-1}"
fi


exec 101>testfile
exec 100<testfile
exec 100>&-
exec 101>&-

# expecting an entry like this:
#10 0000000000000000000000000000000000000000 ima-ng sha1:0000000000000000000000000000000000000000 /run/imatest/rootfs/testfile
ctr=$(grep -c -E "^10 [0]{40} ${imatemplate} ${imahash}:[0]{${hashlen}} .*rootfs/testfile" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find 1 entry for violation in container, found ${ctr}."
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
