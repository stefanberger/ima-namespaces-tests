#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC1091
#set -x

#
# Run tests with SELinux policy labels

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_allow_expensive_test

check_root

check_selinux_enabled

if ! type -p semodule | grep -q ^; then
  echo " Error: semodule tool is not installed"
  exit "${SKIP:-3}"
fi

SELINUX_LABEL="vmtools_exec_t"
SELINUX_MODULE="vmtools"

if ! semodule -l | grep -q "${SELINUX_MODULE}"; then
  echo " Error: SELinux module ${SELINUX_MODULE} is not available"
  exit "${SKIP:-3}"
fi

check_ima_support

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${ROOT}/check.sh" \
	"${DIR}/selinux-labels.sh"

# requires check.sh
if ! check_ns_selinux_support; then
  echo " Error: IMA does not support SELinux labels"
  exit "${SKIP:-3}"
fi

rootfs="$(get_busybox_container_root)"

# First container is just running the script on the host
FAILFILE="failfile"
CMDFILE="cmdfile"
SYNCFILE="syncfile"

testcase=1
while [ "${testcase}" -le 3 ]; do

  case "${testcase}" in
  1) num=2;;
  2) num=$(( $(nproc) ));;
  3) num=$(( $(nproc) * 10));;
  esac

  echo "INFO: Testing disabling SELinux labels with ${num} containers"

  pushd "${rootfs}" &>/dev/null || exit 1
  NSID=0 NUM_CONTAINERS=$((1+num)) \
    CMDFILE="${rootfs}/${CMDFILE}" \
    SYNCFILE="${rootfs}/${SYNCFILE}" \
    FAILFILE="${rootfs}/${FAILFILE}" \
    SELINUX_MODULE=${SELINUX_MODULE} \
    PATH=${rootfs}/bin/:${rootfs}/usr/bin/:${rootfs}/sbin/ \
      ./selinux-labels.sh &
  popd &>/dev/null || exit 1

  for ((i=1; i<=num; i++)); do
    NSID=${i} \
      CMDFILE=${CMDFILE} \
      SYNCFILE=${SYNCFILE} \
      FAILFILE=${FAILFILE} \
      SELINUX_LABEL=${SELINUX_LABEL} \
      run_busybox_container ./selinux-labels.sh &
  done

  wait

  if [ -f "${rootfs}${FAILFILE}" ]; then
    echo "Error: Test ${testcase} failed"
    exit "${FAIL:-1}"
  fi

  echo "INFO: Pass test ${testcase}"
  testcase=$((testcase + 1))
done

exit "${SUCCESS:-0}"
