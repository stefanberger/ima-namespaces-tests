#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC3028

# This script is expected to run in a new session keyring where we create another
# _ima keyring and load CERT2 onto it and sign a new file with KEY2. This file
# must NOT be executable since this is just a new session keyring.

. ./ns-common.sh

echo "  INFO: In key session"

keyctl newring _ima @s 1>/dev/null 2>&1

if ! err=$(keyctl padd asymmetric "" %keyring:_ima < "${CERT2}" 2>&1); then
  echo " Error: Could not load ${CERT2} onto _ima keyring: ${err}"
  exit "${FAIL:-1}"
fi

# Check that unsigned file does not run
if "${TESTFILE}" 2>/dev/null; then
  echo " Error: Executing unsigned testfile must have failed"
  exit "${FAIL:-1}"
fi

# Sign with KEY2
if ! err=$(evmctl ima_sign --imasig --key "${KEY2}" -a sha256 "${TESTFILE}" 2>&1); then
   echo " Error: Could not sign ${TESTFILE}: ${err}"
   exit "${FAIL:-1}"
fi

# It still must not run
if "${TESTFILE}" 2>/dev/null; then
  echo " Error: Executing testfile signed with bad key must have failed"
  exit "${FAIL:-1}"
fi

# Sanity check by signing with KEY
if ! err=$(evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${TESTFILE}" 2>&1); then
  echo " Error: Could not sign ${TESTFILE}: ${err}"
  exit "${FAIL:-1}"
fi

# Now it must run
if ! "${TESTFILE}" 1>/dev/null; then
  echo " Error: Executing testfile signed with good key (${KEY}) must work!"
  exit "${FAIL:-1}"
fi

echo "  INFO: Test in key session passed"

exit "${SUCCESS:-0}"
