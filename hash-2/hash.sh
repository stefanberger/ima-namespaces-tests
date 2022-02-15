#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC2143

. ./ns-common.sh

SYNCFILE=${SYNCFILE:-syncfile}

mnt_securityfs "/mnt"

policy='hash func=FILE_CHECK mask=MAY_READ \n'

printf "${policy}" > /mnt/ima/policy || {
  echo " Error: Could not set appraise+hash policy. Does IMA-ns support IMA-appraise and hash rules?"
  exit "${SKIP:-3}"
}

printf "Hello " >> "${TESTFILE}"
# This cat here is necessary but the hash in security.ima does NOT show up yet
cat < "${TESTFILE}" >/dev/null
getfattr -m ^security.ima -e hex --dump "${TESTFILE}"

printf "world\n" >> "${TESTFILE}"
# Now we must have the hash in security.ima
if [ -z "$(getfattr -m ^security.ima -e hex --dump "${TESTFILE}" | grep ima)" ]; then
  echo " Error: File should have a hash now but it does NOT have one"
  exit "${FAIL:-1}"
fi

# Tell host to run its own test
echo > "${SYNCFILE}"

# Wait for host to tell it's done
if ! wait_file_gone "${SYNCFILE}" 30; then
  echo " Error: Host did not remove ${SYNCFILE} in time"
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
