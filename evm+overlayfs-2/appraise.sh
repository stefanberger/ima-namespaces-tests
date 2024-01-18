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
if ! err=$(keyctl padd asymmetric "" %keyring:_evm < "${CERT}" 2>&1); then
  echo " Error: Could not load key onto _evm keyring: ${err}"
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
TEST_HMAC="${workdir}/overlay/test_hmac"

TEST_RSA_PORTABLE_LOWER="${workdir}/lower/test_rsa_portable"
TEST_RSA_PORTABLE="${workdir}/overlay/test_rsa_portable"
TEST_RSA_PORTABLE2_LOWER="${workdir}/lower/test_rsa_portable2"
TEST_RSA_PORTABLE2="${workdir}/overlay/test_rsa_portable2"
TEST_RSA_PORTABLE3_LOWER="${workdir}/lower/test_rsa_portable3"
TEST_RSA_PORTABLE3_UPPER="${workdir}/upper/test_rsa_portable3"
TEST_RSA_PORTABLE3="${workdir}/overlay/test_rsa_portable3"

# Create test executable; one will be HMAC-signed, the other other one RSA-signed
cat << _EOF_ > "${TEST_HMAC_LOWER}"
#!/bin/sh
echo "works!"
_EOF_
chmod 755 "${TEST_HMAC_LOWER}"
cp "${TEST_HMAC_LOWER}" "${TEST_RSA_PORTABLE_LOWER}"
cp "${TEST_HMAC_LOWER}" "${TEST_RSA_PORTABLE2_LOWER}"
cp "${TEST_HMAC_LOWER}" "${TEST_RSA_PORTABLE3_LOWER}"

# To be able to write security.evm set EVM_ALLOW_METADATA flag
echo $((EVM_ALLOW_METADATA_WRITES)) > "${SECURITYFS_MNT}/evm"
printf "  Configuring EVM with EVM_ALLOW_METADATA_WRITES flag: "
cat "${SECURITYFS_MNT}/evm" ; echo

if ! evm_sign_files_hmac "${KEY}" "${TEST_HMAC_LOWER}"; then
  exit_test "${FAIL:-1}"
fi

# must use --portable for signing to work at all
for fn in "${TEST_RSA_PORTABLE_LOWER}" "${TEST_RSA_PORTABLE2_LOWER}" "${TEST_RSA_PORTABLE3_LOWER}" ; do
  if ! err=$(evmctl sign --imasig --key "${KEY}" -a sha256 --portable "${fn}" 2>&1); then
    echo "Error: Could not sign ${fn}"
    echo "${err}"
    exit_test "${FAIL:-1}"
  fi
done

policy='appraise func=BPRM_CHECK mask=MAY_EXEC fsname=overlay \n'\
'measure func=BPRM_CHECK mask=MAY_EXEC fsname=overlay \n'

if ! printf "${policy}" > "${SECURITYFS_MNT}/ima/policy"; then
  echo " Error: Could not set appraise policy. Does IMA support IMA-appraise?"
  exit_test "${FAIL:-1}"
fi

printf "  Configuring EVM to enforce RSA signatures: "
if ! echo $((EVM_INIT_X509 | EVM_SETUP_COMPLETE)) > "${SECURITYFS_MNT}/evm" 2>/dev/null; then
  echo
  echo " Error: Could not activate EVM with HMAC key."
  cat "${SECURITYFS_MNT}/evm" ; echo
  exit_test "${FAIL:-1}"
fi
cat "${SECURITYFS_MNT}/evm"; echo

# Test file is fully signed and must execute
if ! "${TEST_RSA_PORTABLE}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could not run test file"
  exit_test "${FAIL:-1}"
fi
echo "Successfully ran test with RSA-signed file"

filesize_overlay=$(stat -c"%s" "${TEST_RSA_PORTABLE}")

# Append to file and verify that security.evm has not changed/disappeared
evm_xattr1=$(get_xattr security.evm "${TEST_RSA_PORTABLE}")
if ! echo >> "${TEST_RSA_PORTABLE}"; then
  echo " Error: File modification must be possible."
  exit_test "${FAIL:-1}"
fi

evm_xattr2=$(get_xattr security.evm "${TEST_RSA_PORTABLE}")
if [ "${evm_xattr1}" != "${evm_xattr2}" ]; then
  echo " Error: File modification must NOT have changed xattr."
  echo "  xattr before: ${evm_xattr1}"
  echo "  xattr now   : ${evm_xattr2}"
  exit_test "${FAIL:-1}"
fi

evm_xattr_lower=$(get_xattr security.evm "${TEST_RSA_PORTABLE_LOWER}")
if [ "${evm_xattr1}" != "${evm_xattr_lower}" ]; then
  echo " Error: File modification must not have changed xattr of lower file."
  echo "  xattr_lower: ${evm_xattr_lower}"
  exit_test "${FAIL:-1}"
fi

# File must not execute after file change (due to IMA)
if "${TEST_RSA_PORTABLE}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could run test file after file modifications"
  exit_test "${FAIL:-1}"
fi

# Truncate file to original size
truncate -s "${filesize_overlay}" "${TEST_RSA_PORTABLE}"

# File must execute again
if ! "${TEST_RSA_PORTABLE}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could not run test file after file size truncation"
  exit_test "${FAIL:-1}"
fi
echo "Successfully ran test with RSA-signed file after file truncation"

# Change mode bits on file and verify that security.evm has NOT changed
if ! chmod 777 "${TEST_RSA_PORTABLE}"; then
  echo " Error: File metadata modification must be possible."
  exit_test "${FAIL:-1}"
fi

evm_xattr3=$(get_xattr security.evm "${TEST_RSA_PORTABLE}")
if [ "${evm_xattr2}" != "${evm_xattr3}" ]; then
  echo " Error: File metadata modification must not have changed xattr."
  echo "  xattr before: ${evm_xattr2}"
  echo "  xattr now   : ${evm_xattr3}"
  exit_test "${FAIL:-1}"
fi

evm_xattr_lower=$(get_xattr security.evm "${TEST_RSA_PORTABLE_LOWER}")
if [ "${evm_xattr1}" != "${evm_xattr_lower}" ]; then
  echo " Error: File metadata modification must not have xattr of lower file."
  exit_test "${FAIL:-1}"
fi

# File must not execute after file metadata change
if "${TEST_RSA_PORTABLE}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could run test file after file metadata changes"
  exit_test "${FAIL:-1}"
fi

# Restore mode bits on file
if ! chmod 755 "${TEST_RSA_PORTABLE}"; then
  echo " Error: File metadata modification must be possible."
  exit_test "${FAIL:-1}"
fi

# File must execute again
if ! "${TEST_RSA_PORTABLE}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could not run test file after file size truncation"
  exit_test "${FAIL:-1}"
fi
echo "Successfully ran RSA-signed file after restoring mode bits"

# Must be able to remove security.evm since EVM_ALLOW_METADATA_WRITES
# is still set
if ! setfattr -x security.evm "${TEST_RSA_PORTABLE}"; then
  echo " Error: Could not remove secrutiy.evm from ${TEST_RSA_PORTABLE}"
  exit_test "${FAIL:-1}"
fi

# Test file 2 is fully signed and must execute
if ! "${TEST_RSA_PORTABLE2}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could not run test file 2"
  exit_test "${FAIL:-1}"
fi
echo "Successfully ran test with RSA-signed file 2"

# Change the mode bit on lower -- must prevent file 2 from running
if ! chmod 0777 "${TEST_RSA_PORTABLE2_LOWER}"; then
  echo " Error: Could not change mode bits on ${TEST_RSA_PORTABLE2_LOWER}."
  exit_test "${FAIL:-1}"
fi
if "${TEST_RSA_PORTABLE2}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could run test file 2 even though mode bits have been changed on 'lower'"
  ls -l "${TEST_RSA_PORTABLE2}"
  exit_test "${FAIL:-1}"
fi
echo "Successfully ran test with RSA-signed file 2 after changing mode bits on 'lower'"
if ! chmod 0755 "${TEST_RSA_PORTABLE2_LOWER}"; then
  echo " Error: Could not change mode bits on ${TEST_RSA_PORTABLE2_LOWER}."
  exit_test "${FAIL:-1}"
fi
if ! "${TEST_RSA_PORTABLE2}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could not run test file 2 even though mode bits have been restored on 'lower'"
  ls -l "${TEST_RSA_PORTABLE2}"
  exit_test "${FAIL:-1}"
fi

# Change the owner uid on the 'lower'
if ! chown 11:0 "${TEST_RSA_PORTABLE2_LOWER}"; then
  echo " Error: Could not change owner uid on ${TEST_RSA_PORTABLE2_LOWER}."
  exit_test "${FAIL:-1}"
fi
if "${TEST_RSA_PORTABLE2}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could run test file 2 even though the owner uid has been changed on 'lower'"
  ls -l "${TEST_RSA_PORTABLE2}"
  exit_test "${FAIL:-1}"
fi
echo "Successfully ran test with RSA-signed file 2 after changing owner uid on 'lower'"
if ! chown 0:0 "${TEST_RSA_PORTABLE2_LOWER}"; then
  echo " Error: Could not change owner uid on ${TEST_RSA_PORTABLE2_LOWER}."
  exit_test "${FAIL:-1}"
fi
if ! "${TEST_RSA_PORTABLE2}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could not run test file 2 even though the owner uid has been restored on 'lower'"
  ls -l "${TEST_RSA_PORTABLE2}"
  exit_test "${FAIL:-1}"
fi

# Change the owner gid on the 'lower'
if ! chown 0:12 "${TEST_RSA_PORTABLE2_LOWER}"; then
  echo " Error: Could not change owner gid on ${TEST_RSA_PORTABLE2_LOWER}."
  exit_test "${FAIL:-1}"
fi
if "${TEST_RSA_PORTABLE2}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could run test file 2 even though the owner gid has been changed on 'lower'"
  ls -l "${TEST_RSA_PORTABLE2}"
  exit_test "${FAIL:-1}"
fi
echo "Successfully ran test with RSA-signed file 2 after changing owner gid on 'lower'"
if ! chown 0:0 "${TEST_RSA_PORTABLE2_LOWER}"; then
  echo " Error: Could not change owner gid on ${TEST_RSA_PORTABLE2_LOWER}."
  exit_test "${FAIL:-1}"
fi
if ! "${TEST_RSA_PORTABLE2}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could not run test file 2 even though the owner gid has been restored on 'lower'"
  ls -l "${TEST_RSA_PORTABLE2}"
  exit_test "${FAIL:-1}"
fi

evm_xattr=$(get_xattr security.evm "${TEST_RSA_PORTABLE2_LOWER}")
# Must be able to remove security.evm since EVM_ALLOW_METADATA_WRITES
# is still set
if ! setfattr -x security.evm "${TEST_RSA_PORTABLE2_LOWER}"; then
  echo " Error: Could not remove secrutiy.evm from ${TEST_RSA_PORTABLE2_LOWER}"
  exit_test "${FAIL:-1}"
fi

# Without security.evm file 2 must not execute anymore; if it does then there's
# something wrong with iint's state not having been reset
if "${TEST_RSA_PORTABLE2}" 2>/dev/null 1>/dev/null; then
  echo " Error: Could run test file 2 even though security.evm has been removed from its 'lower'"
  getfattr -m ^security -e hex --dump "${TEST_RSA_PORTABLE2}"
  getfattr -m ^security -e hex --dump "${TEST_RSA_PORTABLE2_LOWER}"
  exit_test "${FAIL:-1}"
fi
echo "Successfully ran test with RSA-signed file 2"

if ! setfattr -n security.evm -v "${evm_xattr}" "${TEST_RSA_PORTABLE2_LOWER}"; then
  echo " Error: Could not write file 2's security.evm on ${TEST_RSA_PORTABLE2_LOWER}"
  exit_test "${FAIL:-1}"
fi


# Change owner on upper causing copy-up; must not execute
if ! chown 0:12 "${TEST_RSA_PORTABLE2}"; then
  echo " Error: Could not change owner gid on ${TEST_RSA_PORTABLE2}."
  exit_test "${FAIL:-1}"
fi
if "${TEST_RSA_PORTABLE2}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could run test file 2 even though the owner gid has been changed on 'overlay'"
  ls -l "${TEST_RSA_PORTABLE2}"
  exit_test "${FAIL:-1}"
fi
if ! chown 0:0 "${TEST_RSA_PORTABLE2}"; then
  echo " Error: Could not change owner gid on ${TEST_RSA_PORTABLE2}."
  exit_test "${FAIL:-1}"
fi
if ! "${TEST_RSA_PORTABLE2}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could not run test file 2 even though the owner gid has been restored on 'overlay'"
  ls -l "${TEST_RSA_PORTABLE2}"
  exit_test "${FAIL:-1}"
fi

# !!! No file content changes on 'file 2' must have occurred so far for the following tests to be useful

# Modify the file on 'lower'; upper may only executed if CONFIG_OVERLAY_FS_METACOPY is not enabled
# If the hashes of upper and lower are different then CONFIG_OVERLAY_FS_METACOPY is not enabled
filesize_lower=$(stat -c"%s" "${TEST_RSA_PORTABLE2_LOWER}")
if ! echo >> "${TEST_RSA_PORTABLE2_LOWER}"; then
  echo " Error: Could not append to file 2 on 'lower'"
  exit_test "${FAIL:-1}"
fi

filesize_overlay=$(stat -c"%s" "${TEST_RSA_PORTABLE2}")
sha1_lower=$(sha1sum "${TEST_RSA_PORTABLE2_LOWER}" | cut -d" " -f1)
sha1_overlay=$(sha1sum "${TEST_RSA_PORTABLE2}" | cut -d" " -f1)
if [ "${sha1_lower}" = "${sha1_overlay}" ]; then
  # CONFIG_OVERLAY_FS_METACOPY is enabled since change to data on lower
  # caused change to data on overlay
  echo " INFO: CONFIG_OVERLAY_FS_METACOPY seems to be enabled"
  if [ "$(stat -c"%s" "${TEST_RSA_PORTABLE2_LOWER}")" -ne "${filesize_overlay}" ]; then
    echo " NOTE: Overlayfs shows wrong file size!"
  fi
  # file must not execute since file on 'lower' has changed
  if "${TEST_RSA_PORTABLE2}" 2>/dev/null 1>/dev/null; then
    echo " Error: Could run test file 2 on 'overlay' after file content change on 'lower' with CONFIG_OVERLAY_FS_METACOPY disabled"
    exit_test "${FAIL:-1}"
  fi
  echo "Successfully failed to run file 2 on 'overlay' after file content change on 'lower' with CONFIG_OVERLAY_FS_METACOPY disabled"

  # truncate file on lower
  if ! truncate -s "${filesize_lower}" "${TEST_RSA_PORTABLE2_LOWER}"; then
    echo " Error: Could not truncate file 2 on 'lower'"
    exit_test "${FAIL:-1}"
  fi

  if ! "${TEST_RSA_PORTABLE2}" 2>/dev/null 1>/dev/null; then
    echo " Error: Could not run test file 2 on 'overlay' after file content restore on 'lower' with CONFIG_OVERLAY_FS_METACOPY disabled"
    exit_test "${FAIL:-1}"
  fi
  echo "Successfully ran test file 2 on 'overlay' after file content restore on 'lower' with CONFIG_OVERLAY_FS_METACOPY disabled"

  # Cause copy-up of file content
  if ! echo >> "${TEST_RSA_PORTABLE2}"; then
    echo " Error: Could not append to file 2 on 'overlay'"
    exit_test "${FAIL:-1}"
  fi

  # file must not execute on overlay
  if "${TEST_RSA_PORTABLE2}" 2>/dev/null 1>/dev/null; then
    echo " Error: Could run test file 2 on 'overlay' after file content change on 'overlay' with CONFIG_OVERLAY_FS_METACOPY disabled"
    exit_test "${FAIL:-1}"
  fi
  echo "Successfully failed to run file 2 on 'overlay' after file content change on 'overlay' with CONFIG_OVERLAY_FS_METACOPY disabled"

  # Restore original file content
  if ! truncate -s "${filesize_lower}" "${TEST_RSA_PORTABLE2}"; then
    echo " Error: Could not truncate file 2 on 'overlay'"
    exit_test "${FAIL:-1}"
  fi

  # file must execute again on overlay
  if ! "${TEST_RSA_PORTABLE2}" 2>/dev/null 1>/dev/null; then
    echo " Error: Could not run test file 2 on 'overlay' after file content restore on 'overlay' with CONFIG_OVERLAY_FS_METACOPY disabled"
    exit_test "${FAIL:-1}"
  fi
  echo "Successfully ran test file 2 on 'overlay' after file content restore on 'overlay' with CONFIG_OVERLAY_FS_METACOPY disabled"

  # Append byte on 'lower'; since copy-up of file content happened file 2 on 'upper' must be independent
  if ! echo >> "${TEST_RSA_PORTABLE2_LOWER}"; then
    echo " Error: Could not append to file 2 on 'lower'"
    exit_test "${FAIL:-1}"
  fi

  # file 2 must still execute on overlay
  if ! "${TEST_RSA_PORTABLE2}" 2>/dev/null 1>/dev/null; then
    echo " Error: Could not run test file 2 on 'overlay' after file content change on 'lower' after copy-up of data with CONFIG_OVERLAY_FS_METACOPY disabled"
    exit_test "${FAIL:-1}"
  fi
  echo "Successfully ran test file 2 on 'overlay' after file content change on 'lower' after copy-up of data with CONFIG_OVERLAY_FS_METACOPY disabled"
fi

echo

# Test file 3 is fully signed and must execute
if ! "${TEST_RSA_PORTABLE3}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could not run test file 3"
  exit_test "${FAIL:-1}"
fi
echo "Successfully ran test with RSA-signed file 3"

# Cause a copy-up
if ! chmod 0777 "${TEST_RSA_PORTABLE3}"; then
  echo " Error: Could not change mode bits on ${TEST_RSA_PORTABLE3}."
  exit_test "${FAIL:-1}"
fi

# File must not execute on overlay
if "${TEST_RSA_PORTABLE3}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could run test file 3 afeter copy-up due to metadata change"
  exit_test "${FAIL:-1}"
fi
echo "Successfully failed to run RSA-signed file 3 after changing of mode bits on 'overlay'"

if ! chmod 0755 "${TEST_RSA_PORTABLE3}"; then
  echo " Error: Could not revert mode bits on ${TEST_RSA_PORTABLE3}."
  exit_test "${FAIL:-1}"
fi

# Test file 3 mode bits are corrected and must execute again
if ! "${TEST_RSA_PORTABLE3}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could not run test file 3 after correcting of mode bits on 'overlay'"
  exit_test "${FAIL:-1}"
fi
echo "Successfully ran test with RSA-signed file 3 after correcting mode bits on 'overlay'"

if ! chmod 0777 "${TEST_RSA_PORTABLE3_UPPER}"; then
  echo " Error: Could not change mode bits on ${TEST_RSA_PORTABLE3_UPPER}."
  exit_test "${FAIL:-1}"
fi

# Test file 3 mode bits are modified and it must not execute
if "${TEST_RSA_PORTABLE3}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could run test file 3 after modification of mode bits on 'upper'"
  exit_test "${FAIL:-1}"
fi
echo "Successfully failed to run RSA-signed file 3 after changing mode bits on 'upper'"

if ! chmod 0755 "${TEST_RSA_PORTABLE3_UPPER}"; then
  echo " Error: Could not change mode bits on ${TEST_RSA_PORTABLE3_UPPER}."
  exit_test "${FAIL:-1}"
fi

if ! "${TEST_RSA_PORTABLE3}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could NOT run test file 3 after correcting of mode bits on 'overlay'"
  exit_test "${FAIL:-1}"
fi
echo "Successfully ran test with RSA-signed file 3 after correcting of mode bits on 'upper'"

if ! chmod 0770 "${TEST_RSA_PORTABLE3}"; then
  echo " Error: Could not change mode bits on ${TEST_RSA_PORTABLE3}."
  exit_test "${FAIL:-1}"
fi

if "${TEST_RSA_PORTABLE3}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could run test file 3 after modification of mode bits on 'overlay'"
  exit_test "${FAIL:-1}"
fi
echo "Successfully failed to run RSA-signed file 3 after modification of mode bits on 'overlay'"

if ! chmod 0755 "${TEST_RSA_PORTABLE3}"; then
  echo " Error: Could not revert mode bits on ${TEST_RSA_PORTABLE3}."
  exit_test "${FAIL:-1}"
fi

if ! "${TEST_RSA_PORTABLE3}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could run test file 3 after correcting of mode bits on 'overlay'"
  exit_test "${FAIL:-1}"
fi
echo "Successfully ran test with RSA-signed file 3 after correcting of mode bits on 'overlay'"

# open file for writing now causing data copy-up if METACOPY is enabled
exec 9>>"${TEST_RSA_PORTABLE3}"
exec 9>&-

if ! "${TEST_RSA_PORTABLE3}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could run test file 3 after opening file for writing on 'overlay'"
  exit_test "${FAIL:-1}"
fi
echo "Successfully ran test with RSA-signed file 3 after opening the file for writing on 'overlay'"

echo

# New file creation must work
NEWFILE="${TEST_RSA_PORTABLE}.new"
if ! echo -en "#!/bin/sh\necho test\n" > "${NEWFILE}" ; then
  echo " Error: Could not create a new file on the overlay"
  exit_test "${FAIL:-1}"
fi

if ! chmod 777 "${NEWFILE}"; then
  echo " Error: Could not modify mode bits on new file on the overlay"
  exit_test "${FAIL:-1}"
fi

# File must not execute at this point: missing signatures
if "${NEWFILE}"; then
  echo " Error: Could execute newly created file on the overlay without any signature"
  exit_test "${FAIL:-1}"
fi
echo "Successfully failed to run new file"

# IMA-sign file
evmctl ima_sign --key "${KEY}" --uuid -a sha256 "${NEWFILE}" >/dev/null 2>&1
if [ -z "$(getfattr -m ^security.ima -e hex --dump "${NEWFILE}" 2>/dev/null)" ]; then
  echo " Error: security.ima should be there now for ${NEWFILE}"
  exit_test "${FAIL:-1}"
fi

# File must not execute at this point: missing EVM signature
if "${NEWFILE}"; then
  echo " Error: Could execute newly created file on the overlay without EVM signature"
  exit_test "${FAIL:-1}"
fi
echo "Successfully failed to run new file without security.evm"

# EVM-sign file with HMAC key using default key
# evmctl hmac doesn't work due to ioctl() to get generation
setfattr -n security.evm -v 0x029787f7fdb78c3710bc479d9338d80593d7dea5d9 "${NEWFILE}"
if [ -z "$(getfattr -m ^security.evm -e hex --dump "${NEWFILE}" 2>/dev/null)" ]; then
  echo " Error: security.evm should be there now for ${NEWFILE}"
  exit_test "${FAIL:-1}"
fi

# File must not execute at this point: need an RSA EVM signature
if "${NEWFILE}"; then
  echo " Error: Could execute newly created file on the overlay with HMAC signature"
  exit_test "${FAIL:-1}"
fi
echo "Successfully failed to run new file with an HMAC signature (need RSA)"

# EVM-sign file with RSA key
evmctl sign --portable --key "${KEY}" --uuid -a sha256 "${NEWFILE}" >/dev/null 2>&1
if [ -z "$(getfattr -m ^security.evm -e hex --dump "${NEWFILE}" 2>/dev/null)" ]; then
  echo " Error: security.evm should be there now for ${NEWFILE}"
  exit_test "${FAIL:-1}"
fi

# File must execute at this point
if ! "${NEWFILE}" 2>/dev/null 1>/dev/null; then
  echo " Error: Could not execute newly created file with all necessary signatures"
  exit_test "${FAIL:-1}"
fi
echo "Successfully ran RSA-signed new file after applying all signatures"

# Add security.SMACK64 to the xattrs that need to be signed
# For testing purposes we do this late. iint caches won't be
# reset, so it will execute now with it.
echo "security.SMACK64" > "${SECURITYFS_MNT}/integrity/evm/evm_xattrs"

# It should run
if ! "${NEWFILE}" 2>/dev/null 1>/dev/null; then
  echo " Error: Could not execute newly created file on the overlay after adding security.SMACK64"
  exit_test "${FAIL:-1}"
fi
echo "Successfully failed to run new file"

if ! setfattr -n security.SMACK64 -v Rubble "${NEWFILE}"; then
  echo " Error: Could not write security.SMACK64"
  exit_test "${FAIL:-1}"
fi

# File must not run now that security.SMACK64 has been set
if "${NEWFILE}" 2>/dev/null 1>/dev/null; then
  echo " Error: Could execute newly created file on the overlay after setting security.SMACK64 but not re-signing"
  exit_test "${FAIL:-1}"
fi
echo "Successfully failed to run new file"

# EVM-sign file with RSA key
evmctl sign --portable --key "${KEY}" --uuid --smack -a sha256 "${NEWFILE}" >/dev/null 2>&1
if [ -z "$(getfattr -m ^security.evm -e hex --dump "${NEWFILE}" 2>/dev/null)" ]; then
  echo " Error: security.evm should be there now for ${NEWFILE}"
  exit_test "${FAIL:-1}"
fi

# File must run now that security.SMACK64 has been set
if ! "${NEWFILE}" 2>/dev/null 1>/dev/null; then
  echo " Error: Could not execute newly created file on the overlay after setting security.SMACK64 and re-signing"
  exit_test "${FAIL:-1}"
fi
echo "Successfully ran new file after signing security.SMACK64"



# HMAC'ed file will never execute since we require RSA signatures
if "${TEST_HMAC}" 2>/dev/null 1>/dev/null; then
  echo "Error: Could run test with HAMC'ed file"
  exit_test "${FAIL:-1}"
fi

if ! evm_xattr=$(get_xattr "security.evm" "${TEST_HMAC}"); then
  echo " Error: Could not get security.evm xattr from previously HAMC'ed file"
  exit_test "${FAIL:-1}"
fi

# HAMC'ed file is allowing the copy-up but security.evm will be lost
if ! echo >> "${TEST_HMAC}"; then
  echo " Error: Could not modify previously HAMC'ed file"
  exit_test "${FAIL:-1}"
fi

if ! evm_xattr=$(get_xattr "security.evm" "${TEST_HMAC}"); then
  echo " Error: Could not get security.evm xattr from previously HAMC'ed file"
  exit_test "${FAIL:-1}"
fi
if [ -n "${evm_xattr}" ]; then
  echo " Error: There should be no security.evm anymore (lost during copy-up)"
  exit_test "${FAIL:-1}"
fi

# Metadata file changes should be allowed now that the file has no security.evm anymore
if ! chmod 777 "${TEST_HMAC}"; then
  echo " Error: Could not modify previously HAMC'ed file's metadata"
  exit_test "${FAIL:-1}"
fi
echo "Successfully tested with HAMC'ed file"

# Since EVM_ALLOW_METADATA_WRITES is set we can write any signature; no point testing

exit_test "${SUCCESS:-0}"
