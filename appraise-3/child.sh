#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059
#set -x

# Calling script needs to set the following variables:
# SYNCFILE: File for synchronization
# CMDFILE:  File to receive commands in
# FAILFILE: File to leave error code in
SYNCFILE=${SYNCFILE:-syncfile}
CMDFILE=${CMDFILE:-cmdfile}

. ./ns-common.sh

mnt_securityfs "/mnt"

i=1
while :; do
  wait_in_cage 1 "${SYNCFILE}-${i}"

  case "$(cat "${CMDFILE}")" in
  execute-fail)
    if "${TESTEXEC}" echo test 2>/dev/null; then
      echo " Error in child: Could execute ${TESTEXEC} even though it should not work."
      echo "${FAIL:-1}" > "${FAILFILE}"
    else
      echo " Child: Executing ${TESTEXEC} failed successfully"
    fi
    ;;
  execute-success)
    if ! "${TESTEXEC}" echo test 2>/dev/null; then
      echo " Error in child: Could NOT execute ${TESTEXEC} even though it should work."
      echo "${FAIL:-1}" > "${FAILFILE}"
      getfattr -m ^security -e hex --dump "${TESTEXEC}"
    else
      echo " Child: Executing ${TESTEXEC} succeeded"
    fi
    ;;
  end)
    break
    ;;
  esac
  i=$((i + 1))
done
