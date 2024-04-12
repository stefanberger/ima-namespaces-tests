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

  for d in 1-overlay 1-lower 1-upper 1-work 2-overlay 2-upper 2-work; do
    mkdir "${rootfs}/${d}"
  done

  if ! mount \
	-t overlay \
	-o "rw,relatime,lowerdir=${rootfs}/1-lower,upperdir=${rootfs}/1-upper,workdir=${rootfs}/1-work" \
	cow "${rootfs}/1-overlay" ||
     ! mount \
	-t overlay \
	-o "rw,relatime,lowerdir=${rootfs}/1-overlay,upperdir=${rootfs}/2-upper,workdir=${rootfs}/2-work" \
	cow "${rootfs}/2-overlay"; then
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

TEST_FILE_1_LOWER="${workdir}/1-lower/test_file"
TEST_FILE_1_UPPER="${workdir}/1-upper/test_file"
TEST_FILE_1_OVERLAY="${workdir}/1-overlay/test_file"
TEST_FILE="${workdir}/2-overlay/test_file"

TEST_FILE2_1_LOWER="${workdir}/1-lower/test_file2"
TEST_FILE2_1_UPPER="${workdir}/1-upper/test_file2"
TEST_FILE2_1_OVERLAY="${workdir}/1-overlay/test_file2"
TEST_FILE2="${workdir}/2-overlay/test_file2"

# Create test files
echo testtest > "${TEST_FILE_1_LOWER}"
echo testtest > "${TEST_FILE2_1_LOWER}"

policy='measure func=FILE_CHECK mask=MAY_READ uid=0 fowner=0 \n'

if ! printf "${policy}" > "${SECURITYFS_MNT}/ima/policy"; then
  echo " Error: Could not set measurement policy. Does IMA support IMA-measurement?"
  exit_test "${FAIL:-1}"
fi


exec 8<>${TEST_FILE_1_LOWER}
exec 9<${TEST_FILE_1_OVERLAY}
exec 8>&-
exec 9>&-

# Expecting 1 measurement entry for ${TEST_FILE_1_OVERLAY} and 1 entry like this here
# 10 0000000000000000000000000000000000000000 ima-ng sha256:0000000000000000000000000000000000000000000000000000000000000000 /var/lib/imatest/rootfs/mntpoint/foo
ctr=$(grep -c -E "^10 [0]{40} .* .* .*${TEST_FILE_1_OVERLAY}$" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find 1 entry for violation for ${TEST_FILE_1_OVERLAY}, found ${ctr}."
  cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
  exit_test "${FAIL:-1}"
fi

echo " PASS: Test 1"

exec 8<>${TEST_FILE_1_LOWER}
exec 9<${TEST_FILE}
exec 8>&-
exec 9>&-

ctr=$(grep -c -E "^10 [0]{40} .* .* .*${TEST_FILE}$" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find 1 entry for violation for ${TEST_FILE}, found ${ctr}."
  cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
  exit_test "${FAIL:-1}"
fi

echo " PASS: Test 2"

# Cause copy up to 1-overlay
exec 8>${TEST_FILE_1_OVERLAY}
exec 8>&-

# TEST_FILE_1_LOWER must not cause new violation but TEST_FILE_1_UPPER should

exec 8<>${TEST_FILE_1_LOWER}
exec 9<${TEST_FILE}
exec 8>&-
exec 9>&-

ctr=$(grep -c -E "^10 [0]{40} .* .* .*${TEST_FILE}$" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find 1 entry for violation for ${TEST_FILE}, found ${ctr}."
  cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
  exit_test "${FAIL:-1}"
fi

echo " PASS: Test 3a"

# TEST_FILE_1_UPPER must cause new violation

exec 8<>${TEST_FILE_1_UPPER}
exec 9<${TEST_FILE}
exec 8>&-
exec 9>&-

ctr=$(grep -c -E "^10 [0]{40} .* .* .*${TEST_FILE}$" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 2 ]; then
  echo " Error: Could not find 2 entries for violation for ${TEST_FILE}, found ${ctr}."
  cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
  exit_test "${FAIL:-1}"
fi

echo " PASS: Test 3b"

# TEST_FILE_1_OVERLAY must cause new violation

exec 8<>${TEST_FILE_1_OVERLAY}
exec 9<${TEST_FILE}
exec 8>&-
exec 9>&-

ctr=$(grep -c -E "^10 [0]{40} .* .* .*${TEST_FILE}$" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 3 ]; then
  echo " Error: Could not find 3 entries for violation for ${TEST_FILE}, found ${ctr}."
  cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
  exit_test "${FAIL:-1}"
fi

echo " PASS: Test 3c"


# Cause metadata copy-up to 2-overlay
chmod 777 "${TEST_FILE2}"

# Check whether TEST_FILE2_1_LOWER is still visible on the top
echo -n "1234" > "${TEST_FILE2_1_LOWER}"
if [ "$(cat "${TEST_FILE2}")" = "1234" ]; then
  echo " INFO: CONFIG_OVERLAY_FS_METACOPY is enabled"

  # TEST_FILE2_1_LOWER must cause violation
  exec 8<>${TEST_FILE2_1_LOWER}
  exec 9<${TEST_FILE2}
  exec 8>&-
  exec 9>&-

  ctr=$(grep -c -E "^10 [0]{40} .* .* .*${TEST_FILE2}$" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
  if [ "${ctr}" -ne 1 ]; then
    echo " Error: Could not find 1 entry for violation for ${TEST_FILE2}, found ${ctr}."
    cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
    exit_test "${FAIL:-1}"
  fi

  echo " PASS: Test 4a"

  # TEST_FILE2_1_OVERLAY must cause violation; opening it for writing will create
  # the TEST_FILE2_1_UPPER
  exec 8<>${TEST_FILE2_1_OVERLAY}
  exec 9<${TEST_FILE2}
  exec 8>&-
  exec 9>&-

  ctr=$(grep -c -E "^10 [0]{40} .* .* .*${TEST_FILE2}$" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
  if [ "${ctr}" -ne 2 ]; then
    echo " Error: Could not find 2 entries for violation for ${TEST_FILE2}, found ${ctr}."
    cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
    exit_test "${FAIL:-1}"
  fi

  echo " PASS: Test 4b"

  # TEST_FILE2_1_UPPER exist now and must cause a violation
  exec 8<>${TEST_FILE2_1_UPPER}
  exec 9<${TEST_FILE2}
  exec 8>&-
  exec 9>&-

  ctr=$(grep -c -E "^10 [0]{40} .* .* .*${TEST_FILE2}$" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
  if [ "${ctr}" -ne 3 ]; then
    echo " Error: Could not find 3 entries for violation for ${TEST_FILE2}, found ${ctr}."
    cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
    exit_test "${FAIL:-1}"
  fi

  echo " PASS: Test 4c"
fi

exit_test "${SUCCESS:-0}"
