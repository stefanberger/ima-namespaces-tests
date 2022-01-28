#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2009

#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_root

check_ima_support

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${DIR}/feed-many-rules.sh"

# hardcoded limit number of rules in kernel: 1024
LIMIT_RULES=1024

before=$(grep -c "cause=too-many-rules" "${AUDITLOG}")

LIMIT_RULES=${LIMIT_RULES} NUM_RULES_STEP=15 \
  run_busybox_container ./feed-many-rules.sh
rc=$?
if [ "${rc}" -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "${rc}"
fi

after=$(grep -c "cause=too-many-rules" "${AUDITLOG}")
expected=$((before + 1))
if [ "${expected}" -ne "${after}" ]; then
  echo " Error: Wrong number of 'cause=too-many-rules' entries in audit log."
  echo "        Expected ${expected}, found ${after}."
  exit "${FAIL:-1}"
fi

echo "INFO: Pass test 1"

exit "${SUCCESS:-0}"
