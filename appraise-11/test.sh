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
	"${DIR}/setxattr.sh" \
	"${ROOT}/keys/rsakey.pem"

if check_ns_ima_ns_support; then
  echo " Skip: IMA-ns is supported"
  exit "${SKIP:-3}"
fi

if ! TEST_USER=$(get_test_user); then
  echo " Skip: Could not find a suitable user to run test with"
  exit "${SKIP:-3}"
fi

copy_elf_busybox_container "$(type -P evmctl)"
copy_elf_busybox_container "$(type -P getfattr)"
copy_elf_busybox_container "$(type -P setfattr)"

# Test that security.ima cannot be written in user namespace and IMA namespace

echo "INFO: Testing setxattr failures in user namespace if IMA-ns is not supported"

rootfs=$(get_busybox_container_root)

chown -R "${TEST_USER}:${TEST_USER}" "${rootfs}"

touch "${rootfs}/good"
chown "${TEST_USER}:${TEST_USER}" "${rootfs}/good"

# Create files with different ownership issues that must not be signable
touch "${rootfs}/bad1"
chown "${TEST_USER}:0" "${rootfs}/bad1"

touch "${rootfs}/bad2"
chown "0:${TEST_USER}" "${rootfs}/bad2"

touch "${rootfs}/bad3"
chown "0:0" "${rootfs}/bad3"


for f in "${rootfs}"/good "${rootfs}"/bad*; do

  # The test user MUST NOT be able to sign any files
  setfattr -x security.ima "${f}" 2>/dev/null

  chmod o+r "${ROOT}/keys/rsakey.pem"
  sudo -u "${TEST_USER}" \
    evmctl ima_sign --imasig --key "${ROOT}/keys/rsakey.pem" -a sha256 "${f}" 1>/dev/null 2>&1
  chmod o-r "${ROOT}/keys/rsakey.pem"

  if [ -n "$(getfattr -m ^security.ima "${f}" 2>/dev/null)" ]; then
    echo " Error: User ${TEST_USER} was able to sign ${f}."
    exit "${FAIL:-1}"
  fi

  # root must sign the files
  if ! msg=$(evmctl ima_sign --imasig --key "${ROOT}/keys/rsakey.pem" -a sha256 "${f}" 2>&1); then
    echo " Error: Could not sign ${f}:"
    echo "${msg}"
    exit "${FAIL:-1}"
  fi
done

sudo -u "${TEST_USER}" \
  env PATH=/bin:/usr/bin SECURITYFS_MNT=/mnt IN_NAMESPACE="1" \
      G_HAS_IMA_NS_SUPPORT="${G_HAS_IMA_NS_SUPPORT}" \
  unshare --user --map-root-user --mount-proc \
    --pid --fork --root "${rootfs}" bin/sh ./setxattr.sh
rc=$?
if [ "${rc}" -ne 0 ]; then
  echo " Error: Test failed in IMA namespace"
  exit "${rc}"
fi

echo "INFO: Pass"

exit "${SUCCESS:-0}"
