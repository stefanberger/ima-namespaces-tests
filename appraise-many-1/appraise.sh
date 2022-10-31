#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

#set -x

# shellcheck disable=SC2059,SC2181

# Caller must pass
# NSID: distinct namespace id number
# FAILFILE: name of file to create upon failure
# NUM_CONTAINERS: The number of containers started
NSID=${NSID:-0}

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

KEY=./rsakey.pem
CERT=./rsa.crt

# Since we are sharing the filesystem with many other containers
# make copies of executables we will run later on
BINDIR="/bin-${NSID}"
mkdir "${BINDIR}"

cp "$(which keyctl)"   "${BINDIR}"
cp "$(which evmctl)"   "${BINDIR}"
cp "$(which busybox2)" "${BINDIR}"
cp "$(which busybox)"  "${BINDIR}"

KEYCTL="${BINDIR}/keyctl"
EVMCTL="${BINDIR}/evmctl"
BUSYBOX="${BINDIR}/busybox"
BUSYBOX2="${BINDIR}/busybox2"

"${KEYCTL}" newring _ima @s >/dev/null 2>&1

# We want to see a measurement of the key when it gets loaded
prepolicy="measure func=KEY_CHECK \n"
printf "${prepolicy}" > "${SECURITYFS_MNT}/ima/policy" || {
  echo " Error: Could not set key measurement policy. Does IMA-ns support IMA-measure?"
  exit "${SKIP:-3}"
}

# Synchronize all containers here otherwise we get failures with keyctl padd giving
# Permission denied errors
syncfile="syncfile"
if [ "${NSID}" -eq 0 ]; then
  wait_cage_full "${NSID}" "${syncfile}" "${NUM_CONTAINERS}"
  open_cage "${syncfile}"
else
  wait_in_cage "${NSID}" "${syncfile}"
fi

"${KEYCTL}" padd asymmetric "" %keyring:_ima < "${CERT}" 1>/dev/null

# Expecting measurement of key
ctr=$(grep -c " _ima " "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find measurement of key in container's measurement list."
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

# Sign keyctl & evmctl to be able to use them later on
"${EVMCTL}" ima_sign --imasig --key "${KEY}" -a sha256 "${KEYCTL}" >/dev/null 2>&1
"${EVMCTL}" ima_sign --imasig --key "${KEY}" -a sha256 "${EVMCTL}" >/dev/null 2>&1
if [ -z "$(getfattr -m ^security.ima -e hex --dump "${EVMCTL}" 2>/dev/null)" ]; then
  echo " Error: security.ima should be there now. Is IMA appraisal support enabled?"
  # setting security.ima was only added when appraisal was enable
  exit "${SKIP:-3}"
fi

policy='appraise func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'\
'measure func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'

printf "${policy}" > "${SECURITYFS_MNT}/ima/policy" || {
  echo " Error: Could not set appraise policy. Does IMA-ns support IMA-appraise?"
  exit "${SKIP:-3}"
}

# Using busybox2 must fail since it's not signed
if "${BUSYBOX2}" cat "${SECURITYFS_MNT}/ima/policy" >/dev/null 2>&1; then
  echo " Error: Could execute unsigned files even though appraise policy is active"
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

"${EVMCTL}" ima_sign --imasig --key "${KEY}" -a sha256 "${BUSYBOX2}" >/dev/null 2>&1
"${EVMCTL}" ima_sign --imasig --key "${KEY}" -a sha256 "${BUSYBOX}"  >/dev/null 2>&1

template=$(PATH=${BINDIR} get_template_from_log "${SECURITYFS_MNT}")
case "${template}" in
ima-sig|ima-ns) num_extra=1;;
*) num_extra=0;;
esac

before=$("${BUSYBOX}" grep -c "${BUSYBOX2}" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")

nspolicy=$("${BUSYBOX2}" cat "${SECURITYFS_MNT}/ima/policy")
policy="${prepolicy}${policy}"
if [ "$(printf "${policy}")" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace ${NSID}."
  echo "expected: |$(printf "${policy}")|"
  echo "actual  : |${nspolicy}|"
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

after=$("${BUSYBOX}" grep -c "${BUSYBOX2}" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
expected=$((before + num_extra))
if [ "${expected}" -ne "${after}" ]; then
  echo " Error: Could not find ${expected} measurement(s) of ${BUSYBOX2} in container, found ${after}."
  "${BUSYBOX}" cat -n "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

"${BUSYBOX}" rm -rf "${BINDIR}"

exit "${SUCCESS:-0}"
