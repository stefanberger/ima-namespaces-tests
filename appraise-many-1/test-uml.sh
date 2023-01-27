#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause
# set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

setup_busybox_container

rootfs="$(get_busybox_container_root)"

cp -rp "${ROOT}" "${rootfs}"

copy_elf_busybox_container "$(type -P busybox)" "bin/"
copy_elf_busybox_container "$(type -P keyctl)"
copy_elf_busybox_container "$(type -P evmctl)"
copy_elf_busybox_container "$(type -P getfattr)"
copy_elf_busybox_container "$(type -P setfattr)"
copy_elf_busybox_container "$(type -P unshare)"
copy_elf_busybox_container "$(type -P bash)" "bin/"

source "${ROOT}/common.sh"

uml_run_script bin/bash /appraise-many-1/test.sh
