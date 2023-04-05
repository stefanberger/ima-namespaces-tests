#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3045

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

KEY=./rsakey.pem
CERT=./rsa.crt

keyctl newring _ima @s >/dev/null 2>&1
keyctl newring _evm @s >/dev/null 2>&1

BUSYBOX=$(which busybox)
TESTFILE=overlay/test

if ! err=$(keyctl padd asymmetric "" %keyring:_ima < "${CERT}" 2>&1); then
  echo " Error: Could not load key onto _ima keyring: ${err}"
  exit_test "${FAIL:-1}"
fi
if ! err=$(keyctl padd asymmetric "" %keyring:_evm < "${CERT}" 2>&1); then
  echo " Error: Could not load key onto _evm keyring: ${err}"
  exit_test "${FAIL:-1}"
fi

# To be able to write security.evm set EVM_ALLOW_METADATA flag
echo $((EVM_ALLOW_METADATA_WRITES)) > "${SECURITYFS_MNT}/evm"
printf "  Configuring EVM with EVM_ALLOW_METADATA_WRITES flag: "
cat "${SECURITYFS_MNT}/evm" ; echo

# Sign tools to be able to use them later on
for t in getfattr setfattr evmctl "${BUSYBOX}"; do
  tool="$(type -P "${t}")"
  evmctl sign --imasig --portable --key "${KEY}" --uuid -a sha256 "${tool}" >/dev/null 2>&1
  if [ -z "$(getfattr -m ^security.ima -e hex --dump "${tool}" 2>/dev/null)" ]; then
    echo " Error: security.ima should be there now."
    exit_test "${FAIL:-1}"
  fi
  if [ -z "$(getfattr -m ^security.evm -e hex --dump "${tool}" 2>/dev/null)" ]; then
    echo " Error: security.evm should be there now."
    exit_test "${FAIL:-1}"
  fi
done

policy='appraise func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'\
'measure func=BPRM_CHECK mask=MAY_EXEC uid=0 fsname=squashfs \n'

if ! printf "${policy}" > "${SECURITYFS_MNT}/ima/policy"; then
  echo " Error: Could not set appraise policy. Does IMA-ns support IMA-appraise?"
  exit_test "${FAIL:-1}"
fi

echo $((EVM_INIT_X509 | EVM_SETUP_COMPLETE)) > "${SECURITYFS_MNT}/evm"
printf "  Configuring EVM to enforce signatures: "
"${BUSYBOX}" cat "${SECURITYFS_MNT}/evm" ; echo

# Unmodified testfile must match IMA signature
if ! err=$(evmctl ima_verify --key "${CERT}" "${TESTFILE}" 2>&1); then
  echo " Error: evmctl could not validate signature of unmodified ${TESTFILE}."
  echo "${err}"
  exit_test "${FAIL:-1}"
fi

# The testfile must work at this point
if ! "${TESTFILE}" 1>/dev/null; then
  echo " Error: Could not execute ${TESTFILE}"
  exit_test "${FAIL:-1}"
fi

filesize=$("${BUSYBOX}" stat -c"%s" "${TESTFILE}")

if [ -z "$(mount | grep lower | grep squashfs)" ]; then
  # Modify lower test file if not on r/o squashfs - TESTFILE must not execute!
  echo >> lower/test

  # Modified testfile must not execute
  if "${TESTFILE}" 2>/dev/null; then
    echo " Error: Could execute ${TESTFILE} even though this must not work (lower/test modification)!"
    exit_test "${FAIL:-1}"
  fi

  # Truncate file to original size
  "${BUSYBOX}" truncate -s "${filesize}" "${TESTFILE}"

  # The testfile must run
  if ! "${TESTFILE}" 1>/dev/null; then
    echo " Error: Could not execute ${TESTFILE}"
    exit_test "${FAIL:-1}"
  fi
  echo "INFO: Passed test with modification on 'lower'."
fi

# modify testfile
echo >> "${TESTFILE}"

# Modified testfile must not match IMA signature
if evmctl ima_verify --key "${CERT}" "${TESTFILE}" 1>/dev/null 2>/dev/null; then
  echo " Error: evmctl could validate signature of modified ${TESTFILE}."
  exit_test "${FAIL:-1}"
fi

# Modified testfile must not execute
if "${TESTFILE}" 2>/dev/null; then
  echo " Error: Could execute ${TESTFILE} even though this must not work!"
  exit_test "${FAIL:-1}"
fi

# Truncate file to original size
"${BUSYBOX}" truncate -s "${filesize}" "${TESTFILE}"

# The testfile must run again
if ! "${TESTFILE}" 1>/dev/null; then
  echo " Error: Could not execute ${TESTFILE}"
  exit_test "${FAIL:-1}"
fi

# Due to fsname=squashfs expecting only boot_aggregate in log
ctr=$(grep -c -E "^" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
exp=1
if [ "${ctr}" -ne "${exp}" ]; then
  echo " Error: Expected ${exp} measurements in log, but found ${ctr}."
  exit_test "${FAIL:-1}"
fi

exit_test "${SUCCESS:-0}"
