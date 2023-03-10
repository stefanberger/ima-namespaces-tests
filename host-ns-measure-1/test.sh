#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"
source "${ROOT}/ns-common.sh"

check_root

check_ima_support

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${ROOT}/uml_chroot.sh" \
	"${ROOT}/check.sh" \
	"${DIR}/measure.sh"

if in_uml; then
  # Due to changing inode pointers under UML this test passes very easily.
  # Therefore, skip it when detecting UML.
  # Otherwise CONFIG_IMA_NS_LOG_CHILD_DUPLICATES=y must be set.
  echo "Skip: Skipping this test when run under UML since it passes 'easily'."
  exit "${SKIP:-3}"
fi

# Check for IMA-ns measurement support; this then also includes template=ima-ns support
if ! check_ns_measure_support; then
  echo "Skip: IMA-ns does not support IMA-measure"
  exit "${SKIP:-3}"
fi

# Set a measurement policy on the host using the ima-ns template
# We want to see multiple measurements of the same file, but only
# one for each IMA-ns.

echo "INFO: Testing measurement of same file started in multiple IMA-ns on host"
echo
echo ">>>>> NOTE: This test requires CONFIG_IMA_NS_LOG_CHILD_DUPLICATES=y"

policy='measure func=BPRM_CHECK mask=MAY_EXEC template=ima-ns '

set_measurement_policy_from_string "${SECURITYFS_MNT}" "${policy}" ""

rootfs="$(get_busybox_container_root)"

TESTFILE="testfile"
testfile="${rootfs}/${TESTFILE}"
imahash=$(determine_file_hash_from_log "${SECURITYFS_MNT}")

cat <<_EOF_ > "${testfile}"
#/bin/env sh
echo ${RANDOM}${RANDOM}
_EOF_
chmod 755 "${testfile}"

filehash=$(hash_file "${imahash}" "${testfile}")

for ((i=1; i<=10; i++)); do
  IMA_TEST_UML="" TESTFILE=${TESTFILE} run_busybox_container ./measure.sh
  rc=$?
  if [ $rc -ne 0 ] ; then
    echo " Error: Test failed in IMA namespace."
    exit "$rc"
  fi
  # cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
  measurementlog_find "${SECURITYFS_MNT}" "^10 .* ima-ns .* .*${filehash}\s+${testfile}\s?\$" "${i}"
done

echo "INFO: Success"

exit "${SUCCESS:-0}"
