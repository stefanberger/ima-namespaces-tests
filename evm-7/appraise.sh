#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3037,SC3045
#set -x

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

KEY=./rsakey.pem
CERT=./rsa.crt

BUSYBOX=$(which busybox)
EVMCTL=$(which evmctl)
TESTFILE=test.txt

keyctl newring _ima @s >/dev/null 2>&1

if ! err=$(keyctl padd asymmetric "" %keyring:_ima < "${CERT}" 2>&1); then
  echo " Error: Could not load key onto _ima keyring: ${err}"
  exit_test "${FAIL:-1}"
fi

# Setup master key
kmk_user="\xB3\x74\xA2\x6A\x71\x49\x04\x37\xAA\x02\x4E\x4F\xAD\xD5\xB4\x97\xFD\xFF\x1A\x8E\xA6\xFF\x12\xF6\xFB\x65\xAF\x27\x20\xB5\x9C\xCF"
if ! keyctl add user kmk-user "${kmk_user}" @s >/dev/null; then
  echo " Error: Could not create key on session keyring"
  exit_test "${FAIL:-1}"
fi

# Setup encrypted evm-key under session keyring!
evmkey="\xB3\x74\xA2\x6A\x71\x49\x04\x37\xAA\x02\x4E\x4F\xAD\xD5\xB4\x97\xFD\xFF\x1A\x8E\xA6\xFF\x12\xF6\xFB\x65\xAF\x27\x20\xB5\x9C\xCF"
mkdir -p /etc/keys
echo -en "${evmkey}" > /etc/keys/evm-key-plain
evmkey_ascii=$(echo -en "${evmkey}"| xxd -c32 -p)
if ! keyctl add encrypted evm-key "new default user:kmk-user 32 ${evmkey_ascii}" @s >/dev/null; then
  echo " Error: Could not create evm-key. Was kernel compiled with CONFIG_USER_DECRYPTED_DATA?"
  exit_test "${FAIL:-1}"
fi

# To be able to write security.evm set EVM_ALLOW_METADATA_WRITES flag
echo $((EVM_ALLOW_METADATA_WRITES)) > "${SECURITYFS_MNT}/evm"
printf "  Configuring EVM with EVM_ALLOW_METADATA_WRITES flag: "
cat "${SECURITYFS_MNT}/evm" ; echo

# Sign tools to be able to use them later on
for t in getfattr evmctl keyctl "${BUSYBOX}"; do
  tool="$(type -P "${t}")"
  evmctl ima_sign --key "${KEY}" --uuid -a sha256 "${tool}" >/dev/null 2>&1
  if [ -z "$(getfattr -m ^security.ima -e hex --dump "${tool}" 2>/dev/null)" ]; then
    echo " Error: security.ima should be there now on ${tool}."
    exit_test "${FAIL:-1}"
  fi
  # Use /etc/keys/evm-key-plain
  # CONFIG_EVM_ATTR_FSUUID MUST NOT BE SET!
  evmctl hmac --uuid -a sha1 -v "${tool}" >/dev/null 2>&1
  if [ -z "$(getfattr -m ^security.evm -e hex --dump "${tool}" 2>/dev/null)" ]; then
    echo " Error: security.evm should be there now on ${tool}."
    exit_test "${FAIL:-1}"
  fi
done

policy='appraise func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'\
'measure func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'

if ! printf "${policy}" > "${SECURITYFS_MNT}/ima/policy"; then
  echo " Error: Could not set appraise policy. Does IMA-ns support IMA-appraise?"
  exit_test "${FAIL:-1}"
fi

printf "  Configuring EVM to enforce HMAC signatures: "
if ! echo $((EVM_INIT_HMAC | EVM_SETUP_COMPLETE)) > "${SECURITYFS_MNT}/evm" 2>/dev/null; then
  echo
  echo " Error: Could not activate EVM with HMAC key."
  cat "${SECURITYFS_MNT}/evm" ; echo
  exit_test "${FAIL:-1}"
fi
cat "${SECURITYFS_MNT}/evm" ; echo

orig_evm=$(getfattr -m ^security.evm -e hex --dump "${EVMCTL}" 2>/dev/null | \
   sed -n 's/^security.evm=\(.*\)/\1/p')

if ! "${EVMCTL}" --help >/dev/null 2>&1; then
  echo " Error: Could not run evmctl."
  echo "   Note: Kernel must NOT have been compiled with CONFIG_EVM_ATTR_FSUUID!"
  exit_test "${FAIL:-1}"
fi

chmod o+w "${EVMCTL}"
new_evm=$(getfattr -m ^security.evm -e hex --dump "${EVMCTL}" 2>/dev/null | \
   sed -n 's/^security.evm=\(.*\)/\1/p')
if [ "${new_evm}" = "${orig_evm}" ]; then
  echo " Error: The EVM HMAC signature must have changed!"
  exit_test "${FAIL:-1}"
fi
if ! "${EVMCTL}" --help >/dev/null 2>&1; then
  echo " Error: Could not run evmctl."
  echo "   Note: Kernel must NOT have been compiled with CONFIG_EVM_ATTR_FSUUID!"
  exit_test "${FAIL:-1}"
fi

chmod o-w "${EVMCTL}"
new_evm=$(getfattr -m ^security.evm -e hex --dump "${EVMCTL}" 2>/dev/null | \
   sed -n 's/^security.evm=\(.*\)/\1/p')
if [ "${new_evm}" != "${orig_evm}" ]; then
  echo " Error: The EVM HMAC signature must have changed back to the original one!"
  exit_test "${FAIL:-1}"
fi
if ! "${EVMCTL}" --help >/dev/null 2>&1; then
  echo " Error: Could not run evmctl."
  echo "   Note: Kernel must NOT have been compiled with CONFIG_EVM_ATTR_FSUUID!"
  exit_test "${FAIL:-1}"
fi

# Create a text file that automatically gets signed (odd ?)
echo -n Test > "${TESTFILE}"
new_evm=$(getfattr -m ^security.evm -e hex --dump "${EVMCTL}" 2>/dev/null | \
   sed -n 's/^security.evm=\(.*\)/\1/p')
if [ -z "${new_evm}" ]; then
  echo " Error: The test file must have an EVM signature but has none."
  exit_test "${FAIL:-1}"
fi
if [ "$(cat "${TESTFILE}")" != "Test" ] ; then
  echo " Error: Could not read from ${TESTFILE}."
  exit_test "${FAIL:-1}"
fi

exit_test "${SUCCESS:-0}"
