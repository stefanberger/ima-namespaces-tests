#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC1091
#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_root_or_sudo

check_ima_support

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${DIR}/reappraise-after-host-file-signing.sh" \
	"${ROOT}/keys/rsakey.pem" \
	"${ROOT}/keys/rsa.crt"

copy_elf_busybox_container "$(type -P keyctl)"
copy_elf_busybox_container "$(type -P evmctl)"
copy_elf_busybox_container "$(type -P getfattr)"
copy_elf_busybox_container "$(type -P setfattr)"

# Test re-appraisal after we sign a file appraised by the namespace from the host
# with a key unknown to the namespace.
# Synchronization of this script and namespace is via shared files
echo "INFO: Testing re-appraisal of file inside container after file signed with unknown key by host"

rootfs="$(get_busybox_container_root)"
SYNCFILE=syncfile
syncfile="${rootfs}/${SYNCFILE}"

TESTEXE=/bin/busybox2
testexe="${rootfs}/${TESTEXE}"

TESTEXE="${TESTEXE}" SYNCFILE="${SYNCFILE}" \
  run_busybox_container ./reappraise-after-host-file-signing.sh &
pid=$!

# Wait until namespace wants us to modify the file
if ! wait_for_file "${syncfile}" 40; then
  echo " Error: Syncfile did not appear!"
else
  # modify the file signature
  if ! sudo evmctl ima_sign --imasig --key "${ROOT}/keys/rsakey2.pem" -a sha256 "${testexe}" >/dev/null 2>&1; then
    echo " Error: Could not sign file on the host"
    exit "${SKIP:-3}"
  fi
  # tell namespace to proceed
  rm -f "${syncfile}"
fi

wait "${pid}"
rc=$?

if [ $rc -ne 0 ]; then
  echo " Error: Test failed in IMA namespace."
  exit "$rc"
fi

echo "INFO: Pass test 1"

exit "${SUCCESS:-0}"
