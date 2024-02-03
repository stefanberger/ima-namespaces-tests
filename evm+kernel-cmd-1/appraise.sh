#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3037
#set -x

. ./ns-common.sh

if ! test -f /proc/keys ; then
  mount -t proc /proc /proc
fi

mnt_securityfs "${SECURITYFS_MNT}"

KEY=./rsakey.pem

# IMA-sign the files with the RSA key $KEY and EVM-sign them with the default HMAC key
sign_files()
{
  for fn in "$@"; do
    evmctl sign --imasig --portable --key "${KEY}" --uuid -a sha256 "${fn}" >/dev/null 2>&1
    if [ -z "$(getfattr -m ^security.ima -e hex --dump "${fn}" 2>/dev/null)" ]; then
      echo " Error: security.ima should be there now for ${fn}."
      return 1
    fi

    if ! err=$(evmctl hmac --uuid -a sha1 -v "${fn}" 2>&1); then
      echo "Error: Could not sign ${fn}"
      echo "${err}"
      return 1
    fi
  done
}

workdir=/workdir
mkdir -p "${workdir}"

if ! evm_setup_keyrings_hmac; then
  exit_test "${FAIL:-1}"
fi

TEST_HMAC="${workdir}/test_hmac"

# Create test file and chmod it to be in IMA policy
echo "test" > "${TEST_HMAC}"

# To be able to write security.evm set EVM_ALLOW_METADATA flag
echo $((EVM_ALLOW_METADATA_WRITES)) > "${SECURITYFS_MNT}/evm"
printf "  Configuring EVM with EVM_ALLOW_METADATA_WRITES flag: "
cat "${SECURITYFS_MNT}/evm" ; echo

if ! sign_files "${TEST_HMAC}"; then
  exit_test "${FAIL:-1}"
fi

# Activate EVM HMAC to see signature changes upon file metadata changes
echo $((EVM_INIT_HMAC)) > "${SECURITYFS_MNT}/evm"
printf "  Configuring EVM with EVM_ALLOW_METADATA_WRITES flag: "
cat "${SECURITYFS_MNT}/evm" ; echo

evm_xattr1=$(get_xattr "security.evm" "${TEST_HMAC}")
if [ -z "${evm_xattr1}" ]; then
  echo " Error: Could not get security.evm or is empty"
  exit_test "${FAIL:-1}"
fi

# Change file metadata
chown 1:2 "${TEST_HMAC}"

evm_xattr2=$(get_xattr "security.evm" "${TEST_HMAC}")
if [ "${evm_xattr1}" = "${evm_xattr2}" ]; then
  echo " Error: The xattr should have changed following 1st file metadata change"
  exit_test "${FAIL:-1}"
fi

# Another change
chown 1:3 "${TEST_HMAC}"

evm_xattr3=$(get_xattr "security.evm" "${TEST_HMAC}")
if [ "${evm_xattr2}" = "${evm_xattr3}" ]; then
  echo " Error: The xattr should have changed following 2nd file metadata change"
  exit_test "${FAIL:-1}"
fi

echo " INFO: Successfully tested with file created before EVM activation"

if ! rm -f "${TEST_HMAC}"; then
  echo " Error: Could not remove file"
  exit_test "${FAIL:-1}"
fi

if ! echo > "${TEST_HMAC}"; then
  echo " Error: Could not create file"
  exit_test "${FAIL:-1}"
fi

if [ -n "$(get_xattr "security.evm" "${TEST_HMAC}")" ]; then
  echo " Error: New file should not have security.evm"
  exit_test "${FAIL:-1}"
fi

if ! err=$(evmctl ima_sign --portable --key "${KEY}" --uuid -a sha256 "${TEST_HMAC}" 2>&1); then
  echo " Error: Could not IMA-sign new file"
  echo "${err}"
  exit_test "${FAIL:-1}"
fi

evm_xattr1="$(get_xattr "security.evm" "${TEST_HMAC}")"
if [ -z "${evm_xattr1}" ]; then
  echo " Error: New file should have security.evm after IMA-signing it"
  exit_test "${FAIL:-1}"
fi

chmod 0777 "${TEST_HMAC}"

evm_xattr2=$(get_xattr "security.evm" "${TEST_HMAC}")
if [ "${evm_xattr1}" = "${evm_xattr2}" ]; then
  echo " Error: The xattr should have changed following file metadata change on new file"
  exit_test "${FAIL:-1}"
fi

echo " INFO: Successfully tested with newly created file"

exit_test "${SUCCESS:-0}"
