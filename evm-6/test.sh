#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC1091
#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_root

check_ima_support

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${ROOT}/scripts/uml_chroot.sh" \
	"${ROOT}/check.sh" \
	"${DIR}/appraise.sh" \
	"${ROOT}/keys/rsakey.pem" \
	"${ROOT}/keys/rsa.crt"

if ! check_ns_evm_support; then
  echo " Skip: IMA-ns does not support EVM in namespaces"
  exit "${SKIP:-3}"
fi
if ! check_ns_appraise_support; then
  echo " Skip: IMA-ns does not support IMA-appraisal in namespaces"
  exit "${SKIP:-3}"
fi

if ! check_overlayfs; then
  echo " Skip: OverlayFS does not seem to be available"
  exit "${SKIP:-3}"
fi

if [ -z "$(type -P mksquashfs)" ]; then
  echo " Skip: Could not find mksquashfs tool"
  exit "${SKIP:-3}"
fi

copy_elf_busybox_container "$(type -P keyctl)"
copy_elf_busybox_container "$(type -P evmctl)"
copy_elf_busybox_container "$(type -P getfattr)"
copy_elf_busybox_container "$(type -P setfattr)"

echo "INFO: Testing enforcement of IMA and EVM signatures inside an IMA+EVM namespace using OverlayFS + SquashFS for 'lower'"


# Build an overlay filesystem under $rootfs
rootfs="$(get_busybox_container_root)"
mkdir "${rootfs}"/{overlay,lower,upper,work}

cat << _EOF_ > "${rootfs}/lower/test"
#!/bin/sh
echo "works!"
_EOF_
chmod 755 "${rootfs}/lower/test"

if ! err=$(evmctl sign --imasig --portable -a sha256 \
	--key "${ROOT}/keys/rsakey.pem" "${rootfs}/lower/test" 2>&1); then
  echo "Error: Could not sign ${rootfs}/lower/test"
  echo "${err}"
  exit "${FAIL:-1}"
fi

rm -f my.squashfs
if ! mksquashfs "${rootfs}/lower" my.squashfs &>/dev/null; then
  echo "Error: Could not create squashfs"
  exit "${FAIL:-1}"
fi

rm -f "${rootfs}/lower/"*

function cleanup()
{
  umount "${rootfs}/overlay"
  umount "${rootfs}/lower"
  rm -f my.squashfs
}
trap cleanup EXIT

if ! mount \
	-t squashfs \
	-o ro,relatime,errors=continue \
	./my.squashfs "${rootfs}/lower"; then
  echo "Error: Could not mount squashfs"
  exit "${FAIL:-1}"
fi

if ! mount \
	-t overlay \
	-o "rw,relatime,lowerdir=${rootfs}/lower,upperdir=${rootfs}/upper,workdir=${rootfs}/work" \
	cow "${rootfs}/overlay"; then
  echo "Error: Could not mount overlay filesystem"
  exit "${FAIL:-1}"
fi

run_busybox_container_key_session ./appraise.sh
rc=$?
if [ $rc -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "$rc"
fi

echo "INFO: Pass"

exit "${SUCCESS:-0}"
