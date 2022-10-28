#!/usr/bin/env bash
#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"
source "${ROOT}/ns-common.sh"

check_root

check_ima_support

check_auditd

set_policy_from_file "${SECURITYFS_MNT}" "${DIR}/ima-policy"

show_policy "${SECURITYFS_MNT}"

create_workdir
TESTFILE="${WORKDIR}/testfile"
cp /bin/true "${TESTFILE}"; echo "${RANDOM}${RANDOM}" >> "${TESTFILE}"

imahash=$(determine_file_hash_from_log "${SECURITYFS_MNT}")
filehash=$(hash_file "${imahash}" "${TESTFILE}")

# Execute the file and wait until something must have appeared in the audit.log
"${TESTFILE}" &>/dev/null

auditlog_find ".*file=\"${TESTFILE}\" hash=\".*${filehash}\" .*" 1 10
measurementlog_find "${SECURITYFS_MNT}" "${filehash}\s+${TESTFILE}\s+\$" 1

mv "${TESTFILE}" "${TESTFILE}.renamed"
"${TESTFILE}.renamed" &>/dev/null

auditlog_find ".*file=\"${TESTFILE}\" hash=\".*${filehash}\" .*" 1 10
measurementlog_find "${SECURITYFS_MNT}" "${filehash}\s+${TESTFILE}\s+\$" 1

auditlog_find ".*file=\"${TESTFILE}.renamed\" hash=\".*${filehash}\" .*" 0 10
measurementlog_find "${SECURITYFS_MNT}" "${filehash}\s+${TESTFILE}renamed\s+\$" 0

echo "INFO: Success"

exit "${SUCCESS:-0}"
