#!/usr/bin/env bash

# shellcheck disable=SC1091
#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_ima_support

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${DIR}/appraise.sh" \
	"${DIR}/reappraise.sh" \
	"${DIR}/reappraise-after-host-file-modification.sh" \
	"${ROOT}/keys/rsakey.pem" \
	"${ROOT}/keys/rsa.crt"

copy_elf_busybox_container "$(type -P keyctl)"
copy_elf_busybox_container "$(type -P evmctl)"
copy_elf_busybox_container "$(type -P getfattr)"
copy_elf_busybox_container "$(type -P setfattr)"

# Test appraisal caused by executable run in namespace

echo "INFO: Testing appraisal inside container"

run_busybox_container ./appraise.sh
rc=$?
if [ $rc -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "$rc"
fi

echo "INFO: Pass test 1"

echo "INFO: Testing re-appraisal inside container"

run_busybox_container ./reappraise.sh
rc=$?
if [ $rc -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "$rc"
fi

echo "INFO: Pass test 2"

# Test re-appraisal after we modify a file appraised by the namespace from the host
# Synchronization of this script and namespace is via shared files
echo "INFO: Testing re-appraisal of file inside container after file modification by host"

rootfs="$(get_busybox_container_root)"
SYNCFILE=syncfile
syncfile="${rootfs}/${SYNCFILE}"

TESTEXE=/bin/busybox2
testexe="${rootfs}/${TESTEXE}"

TESTEXE="${TESTEXE}" SYNCFILE="${SYNCFILE}" \
  run_busybox_container ./reappraise-after-host-file-modification.sh &
pid=$!

# Wait until namespace wants us to modify the file
if ! wait_for_file "${syncfile}" 40; then
  echo " Error: Syncfile did not appear!"
else
  # modify the file
  echo >> "${testexe}"
  # tell namespace to proceed
  rm -f "${syncfile}"
fi

wait "${pid}"
rc=$?

if [ $rc -ne 0 ]; then
  echo " Error: Test failed in IMA namespace."
  exit "$rc"
fi

echo "INFO: Pass test 3"

exit "${SUCCESS:-0}"
