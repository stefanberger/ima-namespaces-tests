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
chmod 777 "${TESTFILE}"

auditcnt=$(grep -c -E " cause=ToMToU .* name=\"${TESTFILE}\"" "${AUDITLOG}")

echo "INFO: Opening ${TESTFILE} for reading and then for writing as root user"
exec 100<"${TESTFILE}"
exec 101>"${TESTFILE}"
exec 101>&-
exec 100>&-

auditlog_find " cause=ToMToU .* name=\"${TESTFILE}\"" "${auditcnt}" 10

echo "INFO: Opening ${TESTFILE} for reading and then for writing as user nobody"
runuser -u nobody -- bash -c "exec 100<\"${TESTFILE}\"; exec 101>\"${TESTFILE}\""

auditlog_find " cause=ToMToU .* name=\"${TESTFILE}\"" "$((auditcnt + 1))" 10

rm -f "${TESTFILE}"

echo "INFO: Test passed"

exit "${SUCCESS:-0}"
