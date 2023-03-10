#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2009

#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_root

check_ima_support

if ! TEST_USER=$(get_test_user); then
  echo " Skip: Could not find a suitable user to test with"
  exit "${SKIP:-3}"
fi
TEST_USER_UID=$(id -u "${TEST_USER}")
TEST_USER_GID=$(id -g "${TEST_USER}")

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${ROOT}/check.sh" \
	"${DIR}/setpolicy.sh"

# Requires check.sh
if ! check_ns_measure_support; then
  echo " Skip: IMA-ns does not support IMA-measure"
  exit "${SKIP:-3}"
fi

rootfs=$(get_busybox_container_root)

echo "INFO: Testing translation of uid and gid values when viewed from other user namespace"

chown -R "${TEST_USER}:${TEST_USER}" "${rootfs}"

SYNCFILE="syncfile"
syncfile="${rootfs}/${SYNCFILE}"
FAILFILE="failfile"
failfile="${rootfs}/${FAILFILE}"

# Unique id for the command line; ignored by the script
id="${RANDOM}abc${RANDOM}"

sudo -u "${TEST_USER}" \
  env PATH=/bin:/usr/bin SYNCFILE=${SYNCFILE} FAILFILE=${FAILFILE} \
  IN_NAMESPACE="1" \
  unshare --user --map-root-user --mount-proc \
    --pid --fork --root "${rootfs}" bin/sh ./setpolicy.sh "${id}" &
for ((i = 0; i < 10; i++)); do
  SHELL_PID=$(ps aux |
    grep -E "^${TEST_USER}" |
    grep "0:00 bin/sh ./setpolicy.sh ${id}" |
    tr -s " " |
    cut -d " " -f2)
  [ -n "${SHELL_PID}" ] && break
  sleep 0.1
done

if ! wait_for_file "${syncfile}" 30; then
  echo " Error: Syncfile did not appear in time"
  exit "${FAIL:-1}"
fi

if [ -f "${failfile}" ]; then
  echo " Error: Failure in the IMA namespace"
  exit "${FAIL:-1}"
fi

# When only entering the mount namespace we see securityfs mounted
# and the uid should show the value relative to the host
rule=$(nsenter --mount -t "${SHELL_PID}" cat "${rootfs}/mnt/ima/policy")
expected=" uid=${TEST_USER_UID} gid=${TEST_USER_GID} "
if ! echo "${rule}" | grep -q "${expected}"; then
  echo " Error: Policy rule does not show adjusted uid!"
  echo "expected to find: |${expected}|"
  echo "rule            : |${rule}|"
  wait
  exit "${FAIL:-1}"
fi

# When entering the mount and user namespaces we see securityfs mounted
# and the uid should show the value relative to that user namespace
rule=$(nsenter --mount --user -t "${SHELL_PID}" cat "${rootfs}/mnt/ima/policy")
expected=" uid=0 gid=0 "
if ! echo "${rule}" | grep -q "${expected}"; then
  echo " Error: Policy rule does not show proper uid!"
  echo "expected to find: |${expected}|"
  echo "rule            : |${rule}|"
  wait
  exit "${FAIL:-1}"
fi

wait

echo "INFO: Pass"

exit "${SUCCESS:-0}"
