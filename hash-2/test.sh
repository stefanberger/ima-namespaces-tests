#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC1091
#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_ima_support

check_host_ima_has_no_rule_like "^hash.*func=FILE_CHECK"

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${ROOT}/check.sh" \
	"${DIR}/hash.sh"

if ! check_ns_hash_support; then
  echo " Skip: IMA-ns does not support IMA-appraise hash rules"
  exit "${SKIP:-3}"
fi

copy_elf_busybox_container "$(type -P getfattr)"

# Test appraisal caused by executable run in namespace

echo "INFO: Testing appraisal inside container"

SYNCFILE="syncfile" TESTFILE="testfile" \
  run_busybox_container ./hash.sh &
childpid=$!
rc=$?
if [ $rc -ne 0 ] ; then
  echo " Error: Test failed to create container."
  exit "$rc"
fi

rootfs=$(get_busybox_container_root)
syncfile="${rootfs}/syncfile"
testfile="${rootfs}/testfile"

if ! wait_for_file "${syncfile}" 50; then
  echo "Error: Syncfile did not appear in time"
  wait_child_exit_with_child_failure "${childpid}"
  exit "${FAIL:-1}"
fi

# Host does NOT have a hash policy rule, so modifying file must not change xattr
echo "INFO: Testing that host modifying file does not cause xattr hash to be re-written"

before=$(getfattr -m ^security.ima -e hex --dump "${testfile}" 2>/dev/null |
         sed -n 's/security.ima=\(.*\)/\1/p')

echo >> "${testfile}"
cat < "${testfile}" >/dev/null
echo >> "${testfile}"

after=$(getfattr -m ^security.ima -e hex --dump "${testfile}" 2>/dev/null |
        sed -n 's/security.ima=\(.*\)/\1/p')

# IMA-ns can terminate now
rm -f "${syncfile}"

if [ "${before}" != "${after}" ]; then
  wait_child_exit_with_child_failure "${childpid}"
  echo "Error: ${testfile}'s xattr has changed!"
  echo "before: ${before}"
  echo "after : ${after}"
  exit "${FAIL:-1}"
fi

wait_child_exit_with_child_failure "${childpid}"

echo "INFO: Pass test 1"

exit "${SUCCESS:-0}"
