#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause
# set -x

. ./ns-common.sh

KEY=./rsakey.pem

# Writing security.ima must fail in a user namespace if there's no IMA-ns support
for f in bad* good*; do
  if evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${f}" >/dev/null 2>&1 ; then
    echo " Error: Could sign file ${f} although this MUST NOT be possible without IMA-ns support!"
    exit "${FAIL:-1}"
  fi
  if [ -z "$(getfattr -m security.ima "${f}" 2>/dev/null)" ]; then
    echo " Error: Root must have signed ${f} before!"
    exit "${FAIL:-1}"
  fi
  if setfattr -x security.ima "${f}" >/dev/null 2>&1; then
    echo " Error: Could remove security.ima although this MUST NOT be possible without IMA-ns support!"
    exit "${FAIL:-1}"
  fi
done

exit "${SUCCESS:-0}"
