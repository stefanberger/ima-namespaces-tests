#!/usr/bin/env bash

#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_root

check_ima_support

for test_user in ftp apache tss nobody; do
  TEST_USER=${test_user}
  if TEST_USER_UID=$(id -u "${TEST_USER}" 2>/dev/null) && \
     TEST_USER_GID=$(id -g "${TEST_USER}" 2>/dev/null); then
    break
  fi
done

if [ -z "${TEST_USER_UID}" ]; then
  echo " Error: Could not find a suitable user to test with"
  exit "${SKIP:-3}"
fi

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${DIR}/setpolicy.sh"

rootfs=$(get_busybox_container_root)

chown -R "${TEST_USER}:${TEST_USER}" "${rootfs}"

SYNCFILE="syncfile"
syncfile="${rootfs}/${SYNCFILE}"
FAILFILE="failfile"
failfile="${rootfs}/${FAILFILE}"

sudo -u "${TEST_USER}" \
  env PATH=/bin:/usr/bin SYNCFILE=${SYNCFILE} FAILFILE=${FAILFILE} \
  unshare --user --map-root-user --mount-proc \
    --pid --fork --root "${rootfs}" bin/sh ./setpolicy.sh &
SUDO_PID=$!
SHELL_PID=$((SUDO_PID + 4))

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
