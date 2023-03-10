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
	"${DIR}/setup-ima.sh" \
	"${DIR}/setrule.sh"

if ! check_ns_audit_support; then
  echo " Skip: IMA-ns does not support IMA-audit"
  exit "${SKIP:-3}"
fi

rootfs=$(get_busybox_container_root)

echo "INFO: Testing setting of audit rules inside another container by host root joining mount namespace"

chown -R "${TEST_USER}:${TEST_USER}" "${rootfs}"

SYNCFILE="syncfile"
syncfile="${rootfs}/${SYNCFILE}"
FAILFILE="failfile"
failfile="${rootfs}/${FAILFILE}"

# Unique id for the command line; ignored by the script
id="${RANDOM}abc${RANDOM}"

# The expected policy
policy="audit func=BPRM_CHECK mask=MAY_EXEC uid=0 gid=0 fowner=0 fgroup=0 "

sudo -u "${TEST_USER}" \
  env PATH=/bin:/usr/bin SYNCFILE=${SYNCFILE} FAILFILE=${FAILFILE} \
  IN_NAMESPACE="1" \
  unshare --user --map-root-user --mount-proc \
    --pid --fork --root "${rootfs}" bin/sh ./setup-ima.sh "${id}" "${policy}" &
for ((i = 0; i < 10; i++)); do
  SHELL_PID=$(ps aux |
    grep -E "^${TEST_USER}" |
    grep "0:00 bin/sh ./setup-ima.sh ${id}" |
    tr -s " " |
    cut -d " " -f2)
  [ -n "${SHELL_PID}" ] && break
  sleep 0.1
done

if ! wait_for_file "${syncfile}" 30; then
  echo " Error: Syncfile did not appear in time"
  exit "${FAIL:-1}"
fi

# Set the policy rule inside the namespace
nsenter --mount -t "${SHELL_PID}" "${rootfs}/setrule.sh" "${policy}" "${rootfs}/mnt/ima/policy"
rc=$?
if [ "${rc}" -ne 0 ]; then
  echo " Error: Error occurred running setrule script in mount namespace"
  exit "${FAIL:-1}"
fi

policy_exp="audit func=BPRM_CHECK mask=MAY_EXEC uid=${TEST_USER_UID} gid=${TEST_USER_GID} fowner=${TEST_USER_UID} fgroup=${TEST_USER_GID} "

# Check that the policy was set
actpolicy=$(nsenter --mount -t "${SHELL_PID}" cat "${rootfs}/mnt/ima/policy")
if [ "${actpolicy}" != "${policy_exp}" ]; then
  echo " Error: Policy in container is different than expected"
  echo " expected: ${policy_exp}"
  echo " actual  : ${actpolicy}"
  exit "${FAIL:-1}"
fi

# Tell the namespace to look at the policy now
rm -f "${syncfile}"

# Wait until namespace is done checking policy
if ! wait_for_file "${syncfile}" 30; then
  echo " Error: Syncfile did not appear in time"
  exit "${FAIL:-1}"
fi

wait

if [ -f "${failfile}" ]; then
  echo " Error: Failure in IMA namespace"
  exit "${FAIL:-1}"
fi

echo "INFO: Pass"

exit "${SUCCESS:-0}"
