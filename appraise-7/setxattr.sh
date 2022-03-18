#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause
# set -x

. ./ns-common.sh

KEY=./rsakey.pem

# Writing security.ima must fail before IMA namespace is active
for f in good*; do
  if evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${f}" >/dev/null 2>&1 ; then
    echo " Error: Could sign file ${f} although this MUST NOT be possible before IMA namespace is active!"
    exit "${FAIL:-1}"
  fi
done

mnt_securityfs "/mnt"

for f in good*; do
  if ! evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${f}" >/dev/null 2>&1 ; then
    echo " Error: Could not sign file ${f} although this MUST be possible"
    ls -l "${f}"
    exit "${FAIL:-1}"
  fi
done

for f in bad*; do
  if evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${f}" >/dev/null 2>&1 ; then
    echo " Error: Could sign file ${f} although this MUST NOT be possible"
    ls -l "${f}"
    exit "${FAIL:-1}"
  fi
done

exit "${SUCCESS:-0}"
