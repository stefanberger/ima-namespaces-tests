#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2009

#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_ima_support

if [ "$(id -u)" -eq 0 ]; then
  if ! TEST_USER=$(get_test_user); then
    echo " Skip: Could not find a suitable user to run test with"
    exit "${SKIP:-3}"
  fi
else
  TEST_USER="$(id -un)"
fi

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${DIR}/fail-setpolicy.sh"

rootfs=$(get_busybox_container_root)

echo "INFO: Testing that non-root user '${TEST_USER}' cannot set audit policy rules"

chown -R "${TEST_USER}:${TEST_USER}" "${rootfs}"

sudo -u "${TEST_USER}" \
  env PATH=/bin:/usr/bin IN_NAMESPACE="1" \
  unshare --user --map-root-user --mount-proc \
    --pid --fork --root "${rootfs}" bin/sh ./fail-setpolicy.sh
rc=$?
if [ "${rc}" -ne 0 ]; then
  echo " Error: Test failed in IMA namespace"
  exit "${rc}"
fi

echo "INFO: Pass"

exit "${SUCCESS:-0}"
