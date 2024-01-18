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

if ! err=$(keyctl padd asymmetric "" %keyring:_ima < "${CERT}" 2>&1); then
  echo " Error: Could not load key onto _ima keyring: ${err}"
  exit_test "${FAIL:-1}"
fi

setup_overlayfs()
{
  rootfs="$1"

  for d in overlay lower upper work; do
    mkdir "${rootfs}/${d}"
  done

  if ! mount \
	-t overlay \
	-o "rw,relatime,lowerdir=${rootfs}/lower,upperdir=${rootfs}/upper,workdir=${rootfs}/work" \
	cow "${rootfs}/overlay"; then
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
TEST_HMAC="${workdir}/overlay/test_hmac"

TEST_HMAC_UNSIGNED_LOWER="${workdir}/lower/test_hmac_unsigned"
TEST_HMAC_UNSIGNED="${workdir}/overlay/test_hmac_unsigned"

# Create test executable; one will be HMAC-signed, the other other one RSA-signed
cat << _EOF_ > "${TEST_HMAC_LOWER}"
#!/bin/sh
echo "works!"
_EOF_
chmod 755 "${TEST_HMAC_LOWER}"
cp "${TEST_HMAC_LOWER}" "${TEST_HMAC_UNSIGNED_LOWER}"

# To be able to write security.evm set EVM_ALLOW_METADATA flag
echo $((EVM_ALLOW_METADATA_WRITES)) > "${SECURITYFS_MNT}/evm"
printf "  Configuring EVM with EVM_ALLOW_METADATA_WRITES flag: "
cat "${SECURITYFS_MNT}/evm" ; echo

if ! evm_sign_files_hmac "${KEY}" "${TEST_HMAC_LOWER}" "${TEST_HMAC_UNSIGNED_LOWER}"; then
  exit_test "${FAIL:-1}"
fi

# Remove security.evm from TEST_HMAC_LOWER_UNSIGNED
if ! setfattr -x security.evm "${TEST_HMAC_UNSIGNED_LOWER}"; then
  echo " Error: Could not remove security.evm from ${TEST_HMAC_UNSIGNED_LOWER} while only EVM_ALLOW_METADATA_WRITES was set."
  exit_test "${FAIL:-1}"
fi

policy='appraise func=BPRM_CHECK mask=MAY_EXEC fsname=overlay \n'\
'measure func=BPRM_CHECK mask=MAY_EXEC fsname=overlay \n'

if ! printf "${policy}" > "${SECURITYFS_MNT}/ima/policy"; then
  echo " Error: Could not set appraise policy. Does IMA support IMA-appraise?"
  exit_test "${FAIL:-1}"
fi

printf "  Configuring EVM to enforce HMAC signatures: "
if ! echo $((EVM_INIT_HMAC | EVM_SETUP_COMPLETE)) > "${SECURITYFS_MNT}/evm" 2>/dev/null; then
  echo
  echo " Error: Could not activate EVM with HMAC key."
  cat "${SECURITYFS_MNT}/evm" ; echo
  exit_test "${FAIL:-1}"
fi

# Executing IMA-signed, EVM-unsigned file must work since EVM_INIT_HMAC is unsupported
if ! "${TEST_HMAC_UNSIGNED}" 2>/dev/null 1>/dev/null; then
  echo " Error: Could not run EVM-unsigned test file on overlay"
  exit_test "${FAIL:-1}"
fi

# Removing security.ima from lower on EVM-unsigned file does not work (not permitted)
# since the file's current integrity is INTEGRITY_NOLABEL
if err=$(setfattr -x security.ima "${TEST_HMAC_UNSIGNED_LOWER}" 2>&1); then
  echo " Error: Could remove security.ima from the lower EVM-unsigned file ${TEST_HMAC_UNSIGNED_LOWER}."
  exit_test "${FAIL:-1}"
fi

# Executing IMA-signed file must work
if ! "${TEST_HMAC}" 2>/dev/null 1>/dev/null; then
  echo " Error: Could not run test file on overlay"
  exit_test "${FAIL:-1}"
fi

# Cannot change file metadata for file that will be on dev=loop1
if chmod 777 "${TEST_HMAC}" 2>/dev/null 1>/dev/null; then
  echo " Error: Could change file metadata on overlay"
  exit_test "${FAIL:-1}"
fi

# Must not be permitted to remove security.evm since EVM_ALLOW_METADATA_WRITES
# was cleared by EVM_INIT_HMAC.
if err=$(setfattr -x security.evm "${TEST_HMAC}" 2>&1); then
  echo " Error: Could remove security.evm from ${TEST_HMAC}"
  exit_test "${FAIL:-1}"
fi

if ! setfattr -x security.evm "${TEST_HMAC_LOWER}"; then
  echo " Error: Could not remove security.evm from lower file ${TEST_HMAC_LOWER}"
  exit_test "${FAIL:-1}"
fi

# Executing IMA-signed, now EVM-unsigned file must still work since HMAC w/o RSA is
# an unsupported config
if ! "${TEST_HMAC}" 2>/dev/null 1>/dev/null; then
  echo " Error: Could not run test file on overlay"
  exit_test "${FAIL:-1}"
fi

# security.ima must not be removable (not permitted) from lower
# since the file's current integrity is INTEGRITY_NOLABEL
if err=$(setfattr -x security.ima "${TEST_HMAC_LOWER}" 2>&1); then
  echo " Error: Could remove security.ima from lower file ${TEST_HMAC_LOWER}"
  exit_test "${FAIL:-1}"
fi

# It must be possible to create a new file on overlay (will be on ext4)
NEWFILE="${TEST_HMAC}.new"
if ! echo -ne "#!/bin/sh\necho Test\n" > "${NEWFILE}" ; then
  echo " Error: Could not create new file on overlay/ext4"
  exit_test "${FAIL:-1}"
fi

# no copy-up involved in this case since file is on ext4
if ! chmod 777 "${NEWFILE}" ; then
  echo " Error: Could not change new file's metadata on overlay/ext4"
  exit_test "${FAIL:-1}"
fi

# New file was created on ext4 rather than overlay, so it won't run
if "${NEWFILE}" 1>/dev/null 2>/dev/null; then
  echo " Error: Could execute new file on overlay/ext4"
  exit_test "${FAIL:-1}"
fi

# It must be possible to create a new file outside the overlay
if ! echo -ne "#!/bin/sh\necho Test\n" > "${workdir}/new"; then
  echo "Error: Could not create new file on ext4"
  exit_test "${FAIL:-1}"
fi

exit_test "${SUCCESS:-0}"
