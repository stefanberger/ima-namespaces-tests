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
CERT=./rsa.crt

keyctl newring _ima @s >/dev/null 2>&1
keyctl newring _evm @s >/dev/null 2>&1

if ! err=$(keyctl padd asymmetric "" %keyring:_ima < "${CERT}" 2>&1); then
  echo " Error: Could not load key onto _ima keyring: ${err}"
  exit_test "${FAIL:-1}"
fi

setup_overlayfs()
{
  workdir="$1"

  for d in overlay lower upper work; do
    mkdir "${workdir}/${d}"
  done

  if ! mount \
	-t overlay \
	-o "rw,relatime,lowerdir=${workdir}/lower,upperdir=${workdir}/upper,workdir=${workdir}/work" \
	cow "${workdir}/overlay"; then
    echo "Error: Could not mount overlay filesystem"
    return 1
  fi

  return 0
}

workdir=/ext4.mount
mkdir -p "${workdir}"

if ! evm_setup_keyrings_hmac; then
  exit_test "${FAIL:-1}"
fi

if ! setup_overlayfs "${workdir}"; then
  exit_test "${FAIL:-1}"
fi

TEST_HMAC_LOWER="${workdir}/lower/test_hmac"

TEST_RSA_PORTABLE_LOWER="${workdir}/lower/test_rsa_portable"
TEST_RSA_PORTABLE="${workdir}/overlay/test_rsa_portable"

# Create test executable; one will be HMAC'ed, the other other one RSA-signed
cat << _EOF_ > "${TEST_HMAC_LOWER}"
#!/bin/sh
echo "works!"
_EOF_
chmod 755 "${TEST_HMAC_LOWER}"
cp "${TEST_HMAC_LOWER}" "${TEST_RSA_PORTABLE_LOWER}"

# To be able to write security.evm set EVM_ALLOW_METADATA flag
echo $((EVM_ALLOW_METADATA_WRITES)) > "${SECURITYFS_MNT}/evm"
printf "  Configuring EVM with EVM_ALLOW_METADATA_WRITES flag: "
cat "${SECURITYFS_MNT}/evm" ; echo

if ! evm_sign_files_hmac "${KEY}" "${TEST_HMAC_LOWER}"; then
  exit_test "${FAIL:-1}"
fi

# must use --portable for signing to work at all
if ! err=$(evmctl sign --imasig --key "${KEY}" -a sha256 --portable "${TEST_RSA_PORTABLE_LOWER}" 2>&1); then
  echo "Error: Could not sign ${TEST_RSA_PORTABLE_LOWER}"
  echo "${err}"
  return 1
fi

policy='appraise func=FILE_CHECK fsname=overlay \n'\
'measure func=FILE_CHECK fsname=overlay \n'

if ! printf "${policy}" > "${SECURITYFS_MNT}/ima/policy"; then
  echo " Error: Could not set appraise policy. Does IMA support IMA-appraise?"
  exit_test "${FAIL:-1}"
fi

printf "  Configuring EVM to enforce RSA signatures: "
if ! echo $((EVM_INIT_X509)) > "${SECURITYFS_MNT}/evm" 2>/dev/null; then
  echo
  echo " Error: Could not activate EVM with HMAC key."
  cat "${SECURITYFS_MNT}/evm" ; echo
  exit_test "${FAIL:-1}"
fi
cat "${SECURITYFS_MNT}/evm"; echo

# Test file must not be accessible
if cat "${TEST_RSA_PORTABLE}" 1>/dev/null 2>/dev/null; then
  echo " Error: Could access file while key is not on _evm keyring"
  exit_test "${FAIL:-1}"
fi

if ! err=$(keyctl padd asymmetric "" %keyring:_evm < "${CERT}" 2>&1); then
  echo " Error: Could not load key onto _evm keyring: ${err}"
  exit_test "${FAIL:-1}"
fi

if ! cat "${TEST_RSA_PORTABLE}" 1>/dev/null 2>/dev/null; then
  echo " Error: Could not access signed file file after key was pu on _evm keyring"
  exit_test "${FAIL:-1}"
fi

# Only setting EVM_INIT_X509 still leaves EVM_ALLOW_METADATA_WRITES set and
# so we can change the mode bits
if ! chmod 0777 "${TEST_RSA_PORTABLE}"; then
  echo " Error: Could not change mode bits on signed file"
  exit_test "${FAIL:-1}"
fi

# Test file must not be accessible
if cat "${TEST_RSA_PORTABLE}" 1>/dev/null 2>/dev/null; then
  echo " Error: Could access file after changing its mode bits"
  exit_test "${FAIL:-1}"
fi

if ! chmod 0755 "${TEST_RSA_PORTABLE}"; then
  echo " Error: Could not change back mode bits on signed file"
  exit_test "${FAIL:-1}"
fi

if ! cat "${TEST_RSA_PORTABLE}" 1>/dev/null 2>/dev/null; then
  echo " Error: Could not access signed file file after restoring mode bits"
  exit_test "${FAIL:-1}"
fi

evm_xattr=$(get_xattr security.evm "${TEST_RSA_PORTABLE}")
# while EVM_ALLOW_METADATA_WRITES is still enabled removing security.evm must be
# possible
if ! setfattr -x security.evm "${TEST_RSA_PORTABLE}"; then
  echo " Error: Could not remove security.evm while EVM_ALLOW_METADATA_WRITES is set"
  exit_test "${FAIL:-1}"
fi

# Test file must not be accessible
if cat "${TEST_RSA_PORTABLE}" 1>/dev/null 2>/dev/null; then
  echo " Error: Could access file after removal of security.evm"
  exit_test "${FAIL:-1}"
fi

# Write back security.evm
if ! setfattr -n security.evm -v "${evm_xattr}" "${TEST_RSA_PORTABLE}"; then
  echo " Error: Could not write security.evm while EVM_ALLOW_METADATA_WRITES is set"
  exit_test "${FAIL:-1}"
fi

printf "  Configuring EVM to enforce RSA and HMAC signatures: "
if ! echo $((EVM_INIT_X509 | EVM_INIT_HMAC | EVM_SETUP_COMPLETE)) > "${SECURITYFS_MNT}/evm" 2>/dev/null; then
  echo
  echo " Error: Could not activate EVM with HMAC key."
  cat "${SECURITYFS_MNT}/evm" ; echo
  exit_test "${FAIL:-1}"
fi
cat "${SECURITYFS_MNT}/evm"; echo

if ! cat "${TEST_RSA_PORTABLE}" 1>/dev/null 2>/dev/null; then
  echo " Error: Could not access signed file after enabling HMAC"
  exit_test "${FAIL:-1}"
fi

# EVM_INIT_HMAC disabled EVM_ALLOW_METADATA_WRITES and therefore we must
# not be able to chmod the file.
# Only setting EVM_INIT_X509 would still allow it, though.
if chmod 0777 "${TEST_RSA_PORTABLE}" 1>/dev/null 2>/dev/null; then
  echo " Error: Could change mode bits on signed file"
  exit_test "${FAIL:-1}"
fi

if setfattr -x security.evm "${TEST_RSA_PORTABLE}" 1>/dev/null 2>/dev/null; then
  echo " Error: Could remove security.evm"
  exit_test "${FAIL:-1}"
fi

exit_test "${SUCCESS:-0}"
