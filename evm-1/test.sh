#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC1091
#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_ima_support

check_root

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${ROOT}/check.sh" \
	"${DIR}/setxattr.sh"

if check_ns_evm_support; then
  echo " Error: IMA-ns does support EVM"
  exit "${SKIP:-3}"
fi

test_users="ftp apache tss nobody"
found=0
for TEST_USER in ${test_users}; do
  if id -u "${TEST_USER}" &>/dev/null && \
     id -g "${TEST_USER}" &>/dev/null; then
    found=1
    break
  fi
done
if [ "${found}" -eq 0 ]; then
  echo " Error: Could not find a suitable user to run test with"
  exit "${SKIP:-3}"
fi

copy_elf_busybox_container "$(type -P setfattr)"

echo "INFO: Testing writing of EVM signature inside IMA namespace"

rootfs=$(get_busybox_container_root)

chown -R "${TEST_USER}:${TEST_USER}" "${rootfs}"

# Although this one has uid and gid mapped, it MUST NOT be signeable
touch "${rootfs}/good"
chown "${TEST_USER}:${TEST_USER}" "${rootfs}/good"

# Create files with different ownership issues that must not be signable

touch "${rootfs}/bad1"
chown "${TEST_USER}:0" "${rootfs}/bad1"

touch "${rootfs}/bad2"
chown "0:${TEST_USER}" "${rootfs}/bad2"

touch "${rootfs}/bad3"
chown "0:0" "${rootfs}/bad3"

sudo -u "${TEST_USER}" \
  env PATH=/bin:/usr/bin SECURITYFS_MNT=/mnt \
  unshare --user --map-root-user --mount-proc \
    --pid --fork --root "${rootfs}" bin/sh ./setxattr.sh
rc=$?
if [ $rc -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "$rc"
fi

echo "INFO: Pass"

exit "${SUCCESS:-0}"
