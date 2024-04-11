#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3037
#set -x

. ./ns-common.sh

if ! test -f /proc/keys ; then
  mount -t proc /proc /proc
fi

mnt_securityfs "${SECURITYFS_MNT}"

setup_overlayfs()
{
  rootfs="$1"

  for d in overlay lower upper work; do
    mkdir "${rootfs}/${d}"
  done

  if ! mount \
	-t overlay \
	-o "rw,relatime,lowerdir=${rootfs}/lower,upperdir=${rootfs}/upper,workdir=${rootfs}/work" \
	cow "${rootfs}/overlay"; then
    echo "Error: Could not mount overlay filesystem"
    return 1
  fi

  return 0
}

workdir=/ext4.mount
mkdir -p "${workdir}"

if ! setup_overlayfs "${workdir}"; then
  exit_test "${FAIL:-1}"
fi

TEST_FILE_LOWER="${workdir}/lower/test_file"
TEST_FILE2_LOWER="${workdir}/lower/test_file2"
TEST_FILE2_UPPER="${workdir}/upper/test_file2"
TEST_FILE2="${workdir}/overlay/test_file2"
TEST_FILE3_LOWER="${workdir}/lower/test_file3"
TEST_FILE3_UPPER="${workdir}/upper/test_file3"
TEST_FILE3="${workdir}/overlay/test_file3"
ROOT_FILE="/foo"

# Create test files
echo testtest > "${TEST_FILE_LOWER}"
cp "${TEST_FILE_LOWER}" "${ROOT_FILE}"
echo testtest2 > "${TEST_FILE2_LOWER}"

policy='measure func=FILE_CHECK mask=MAY_READ uid=0 fowner=0 \n'

if ! printf "${policy}" > "${SECURITYFS_MNT}/ima/policy"; then
  echo " Error: Could not set measurement policy. Does IMA support IMA-measurement?"
  exit_test "${FAIL:-1}"
fi

# basic test for non-stacked filesystems case
exec 8<${ROOT_FILE}
exec 9<>${ROOT_FILE}
exec 8>&-
exec 9>&-


# Expecting 1 measurement entry for ${ROOT_FILE} and 1 entry like this here
# 10 0000000000000000000000000000000000000000 ima-ng sha256:0000000000000000000000000000000000000000000000000000000000000000 /var/lib/imatest/rootfs/mntpoint/foo
ctr=$(grep -c -E "^10 [0]{40} .* .* .*${ROOT_FILE}$" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find 1 entry for violation for ${ROOT_FILE}, found ${ctr}."
  cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
  exit_test "${FAIL:-1}"
fi

echo " PASS: Test 1"

# basic test for non-stacked filesystem case
exec 8<${TEST_FILE_LOWER}
exec 9<>${TEST_FILE_LOWER}
exec 8>&-
exec 9>&-


ctr=$(grep -c -E "^10 [0]{40} .* .* .*${TEST_FILE_LOWER}$" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find 1 entry for violation for ${TEST_FILE_LOWER}, found ${ctr}."
  cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
  exit_test "${FAIL:-1}"
fi

echo " PASS: Test 2"

# since file on lower holds data it must cause a violation
exec 8<>"${TEST_FILE2_LOWER}"
exec 9<"${TEST_FILE2}"
exec 8>&-
exec 9>&-

ctr=$(grep -c -E "^10 [0]{40} .* .* .*${TEST_FILE2}$" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find 1 entry for violation for ${TEST_FILE2}, found ${ctr}."
  cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
  exit_test "${FAIL:-1}"
fi

echo " PASS: Test 3"

# Cause copy-up
if [ -f "${TEST_FILE2_UPPER}" ]; then
  echo " Error: ${TEST_FILE2_UPPER} should not already exist"
  exit_test "${FAIL:-1}"
fi
exec 9>"${TEST_FILE2}"
exec 9>&-

if [ ! -f "${TEST_FILE2_UPPER}" ]; then
  echo " Error: ${TEST_FILE2_UPPER} must exist now"
  exit_test "${FAIL:-1}"
fi

# After copy-up opening the lower file for writing and on overlay for reading must
# not cause a violation anymore
exec 8<>"${TEST_FILE2_LOWER}"
exec 9<"${TEST_FILE2}"
exec 8>&-
exec 9>&-

ctr=$(grep -c -E "^10 [0]{40} .* .* .*${TEST_FILE2}$" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Only 1 entry for violation for ${TEST_FILE2} should be there, found ${ctr}."
  cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
  exit_test "${FAIL:-1}"
fi

echo " PASS: Test 4"

# upper is holding the file data and this must cause a violation
exec 8<>"${TEST_FILE2_UPPER}"
exec 9<"${TEST_FILE2}"
exec 8>&-
exec 9>&-

ctr=$(grep -c -E "^10 [0]{40} .* .* .*${TEST_FILE2}$" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 2 ]; then
  echo " Error: 2 entries for violations for ${TEST_FILE2} should be there, found ${ctr}."
  cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
  exit_test "${FAIL:-1}"
fi

echo " PASS: Test 5"

# New file created only on overlay layer; must cause violation
echo >> "${TEST_FILE3}"
exec 8<>"${TEST_FILE3}"
exec 9<"${TEST_FILE3}"
exec 8>&-
exec 9>&-

ctr=$(grep -c -E "^10 [0]{40} .* .* .*${TEST_FILE3}$" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Only 1 entry for violation for ${TEST_FILE3} should be there, found ${ctr}."
  cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
  exit_test "${FAIL:-1}"
fi

echo " PASS: Test 6"

if [ ! -f "${TEST_FILE3_UPPER}" ]; then
  echo " Error: ${TEST_FILE3_UPPER} must exist"
  exit_test "${FAIL:-1}"
fi

# upper is holding file data and this must cause a violation
exec 8<>"${TEST_FILE3_UPPER}"
exec 9<"${TEST_FILE3}"
exec 8>&-
exec 9>&-

ctr=$(grep -c -E "^10 [0]{40} .* .* .*${TEST_FILE3}$" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 2 ]; then
  echo " Error: 2 entries for violations for ${TEST_FILE3} should be there, found ${ctr}."
  cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
  exit_test "${FAIL:-1}"
fi

echo " PASS: Test 7"

# since upper is holding file data opening lower for r/w must no cause a vilation (file doesn't exist)
exec 8<>"${TEST_FILE3_LOWER}"
exec 9<"${TEST_FILE3}"
exec 8>&-
exec 9>&-

ctr=$(grep -c -E "^10 [0]{40} .* .* .*${TEST_FILE3}$" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 2 ]; then
  echo " Error: 2 entries for violations for ${TEST_FILE3} should be there, found ${ctr}."
  cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
  exit_test "${FAIL:-1}"
fi

echo " PASS: Test 8"

exit_test "${SUCCESS:-0}"
