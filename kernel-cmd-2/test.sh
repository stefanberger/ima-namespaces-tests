#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC1091
#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_allow_expensive_test

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${ROOT}/uml_chroot.sh" \
	"${ROOT}/check.sh"

kv=$(get_kernel_version)
if kernel_version_ge "${kv}" "5.14.0"; then
  # iuid and igid were available only in 5.14.0
  fmt="iuid igid imode|n iuid|igid iuid|igid|imode|d-ng|buf|n-ng"
fi

if kernel_version_ge "${kv}" "5.19.0"; then
  # d-ngv2 became available in 5.19.0
  fmt="${fmt} d-ngv2"
fi

echo "INFO: Testing ima_hash & ima_policy & ima_template_fmt kernel command line parameters"

for hash in \
	sha256 \
	sha512
do
  for template_fmt in \
	d \
	d-ng \
	'd-ng|d-ng' \
	n \
	n-ng \
	buf \
	${fmt:+${fmt}};
  do
    for policy in \
	tcb \
	critical_data \
	"tcb|critical_data";
    do
      # Recreate the container on every loop
      setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${ROOT}/uml_chroot.sh" \
	"${DIR}/check_log_template.sh"

      UML_KERNEL_CMD="ima_policy=${policy} ima_template_fmt=${template_fmt} ima_hash=${hash}" \
        G_IMA_POLICY="${policy}" G_IMA_TEMPLATE_FMT="${template_fmt}" G_IMA_HASH="${hash}" \
        run_busybox_host ./check_log_template.sh
      rc=$?
      if [ $rc -ne 0 ] ; then
        echo " Error: Test with ima_template_fmt='${template_fmt}', ima_policy='${policy}', and ima_hash='${hash}' failed"
        exit "$rc"
      fi
      echo " Test with ima_template_fmt='${template_fmt}', ima_policy='${policy}', and ima_hash='${hash}' passed"
    done
  done
done

echo "INFO: Test passed"
