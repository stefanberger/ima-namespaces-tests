#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

. ./ns-common.sh

TESTFILE=${TESTFILE:-}

# run the testfile
if ! "/${TESTFILE}" 1>/dev/null; then
  echo " Error: Could not run '${TESTFILE}' in IMA-ns"
  exit_test "${FAIL:-1}"
fi

# run the testfile a 2nd time -- this should must not appear in host log
if ! "/${TESTFILE}" 1>/dev/null; then
  echo " Error: Could not run '${TESTFILE}' in IMA-ns"
  exit_test "${FAIL:-1}"
fi

exit_test "${SUCCESS:-0}"
