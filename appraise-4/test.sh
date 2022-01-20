#!/usr/bin/env bash

# shellcheck disable=SC1091
#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_ima_support

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${DIR}/odirect.sh" \
	"${ROOT}/keys/rsakey.pem" \
	"${ROOT}/keys/rsa.crt" \
	"$(type -P ldd)"

copy_elf_busybox_container "$(type -P keyctl)"
copy_elf_busybox_container "$(type -P evmctl)"
copy_elf_busybox_container "$(type -P dd)"

# Test appraisal caused by executable run in namespace

echo "INFO: Testing O_DIRECT usage and appraisal inside container"

run_busybox_container ./odirect.sh
rc=$?
if [ $rc -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "$rc"
fi

echo "INFO: Pass test 1"

exit "${SUCCESS:-0}"
