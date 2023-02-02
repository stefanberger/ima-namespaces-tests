#!/usr/bin/env bash
#set -x

DIR="$(dirname "$0")"
ROOT="${DIR}/.."

source "${ROOT}/common.sh"
source "${ROOT}/ns-common.sh"

check_root

check_ima_support

check_auditd

create_workdir
SRC_IMAPOLICY="${DIR}/ima-policy"
IMAPOLICY="${WORKDIR}/ima-policy"
TESTFILE="${WORKDIR}/testfile"

if ! nobody_uid=$(id nobody -u) || [ -z "${nobody_uid}" ]; then
	echo "Error: Could not get uid of nobody user."
	exit "${FAIL:-1}"
fi

sed "s/%UID%/${nobody_uid}/g" "${SRC_IMAPOLICY}" > "${IMAPOLICY}"
set_policy_from_file "${SECURITYFS_MNT}" "${IMAPOLICY}"

show_policy "${SECURITYFS_MNT}"

echo "${RANDOM}${RANDOM}" >> "${TESTFILE}"
chmod 755 "${TESTFILE}"

imahash=$(determine_file_hash_from_log "${SECURITYFS_MNT}")
filehash=$(hash_file "${imahash}" "${TESTFILE}")

# Read the file as root and wait until something must have appeared in the audit.log
cat "${TESTFILE}" &>/dev/null

auditlog_find ".*file=\"${TESTFILE}\" hash=\".*${filehash}\" .*" 0 10
measurementlog_find "${SECURITYFS_MNT}" "${filehash}\s+${TESTFILE}\s?\$" 0

runuser -u nobody -- cat "${TESTFILE}" &>/dev/null

auditlog_find ".*file=\"${TESTFILE}\" hash=\".*${filehash}\" .*" 1 10
measurementlog_find "${SECURITYFS_MNT}" "${filehash}\s+${TESTFILE}\s?\$" 1

echo "INFO: Success"

exit "${SUCCESS:-0}"
