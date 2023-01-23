#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC1091
#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_allow_expensive_test

echo "INFO: Testing ima_policy kernel command line parameters"

for hash in \
	sha1 \
	sha256 \
	sha384 \
	sha512;
do
  for template in \
	ima-ng \
	ima-ngv2 \
	ima-sig \
	ima-sigv2;
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
	"${DIR}/check_log.sh"

      UML_KERNEL_CMD="ima_policy=${policy} ima_template=${template} ima_hash=${hash}" \
        G_IMA_POLICY="${policy}" G_IMA_TEMPLATE="${template}" G_IMA_HASH="${hash}" \
        run_busybox_host ./check_log.sh
      rc=$?
      if [ $rc -ne 0 ] ; then
        echo " Error: Test with ima_template='${template}', ima_policy='${policy}', and ima_hash='${hash}' failed"
        exit "$rc"
      fi
      echo " Test with ima_template='${template}', ima_policy='${policy}', and ima_hash='${hash}' passed"
    done
  done
done

echo "INFO: Test passed"
