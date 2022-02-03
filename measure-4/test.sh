#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2009

#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"

check_ima_support

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${ROOT}/check.sh" \
	"${DIR}/feed-many-rules.sh"

if ! check_ns_audit_support; then
  echo " Error: IMA-ns does not support IMA-audit"
  exit "${SKIP:-3}"
fi

# hardcoded limit number of rules in kernel: 1024
LIMIT_RULES=1024

echo "INFO: Testing number of rules settable in IMA namespace is limited"

LIMIT_RULES=${LIMIT_RULES} NUM_RULES_STEP=15 \
  run_busybox_container ./feed-many-rules.sh
rc=$?
if [ "${rc}" -ne 0 ] ; then
  echo " Error: Test failed in IMA namespace."
  exit "${rc}"
fi

echo "INFO: Pass test 1"

exit "${SUCCESS:-0}"
