#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059
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

BUSYBOX=$(which busybox)
TESTFILE=./test

if ! err=$(keyctl padd asymmetric "" %keyring:_ima < "${CERT}" 2>&1); then
  echo " Error: Could not load key onto _ima keyring: ${err}"
  exit_test "${FAIL:-1}"
fi
if ! err=$(keyctl padd asymmetric "" %keyring:_evm < "${CERT}" 2>&1); then
  echo " Error: Could not load key onto _evm keyring: ${err}"
  exit_test "${FAIL:-1}"
fi

cat << _EOF_ > "${TESTFILE}"
#!/bin/sh
echo test.sh ran successfully
_EOF_
modebits=0755
chmod "${modebits}" "${TESTFILE}"

# To be able to write security.evm set EVM_ALLOW_METADATA_WRITES flag
echo $((EVM_ALLOW_METADATA_WRITES)) > "${SECURITYFS_MNT}/evm"

for prg in "${TESTFILE}" "${BUSYBOX}" "$(which getfattr)"; do
  if ! err=$(evmctl sign --imasig --portable --key "${KEY}" -a sha256 "${prg}" 2>&1); then
    echo " Error: Could not sign ${prg}: ${err}"
    exit_test "${FAIL:-1}"
  fi
done

policy='appraise func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'\
'measure func=BPRM_CHECK mask=MAY_EXEC uid=0 template=evm-sig \n'

if ! printf "${policy}" > "${SECURITYFS_MNT}/ima/policy"; then
  echo " Error: Could not set appraise policy. Does IMA-ns support IMA-appraise?"
  exit_test "${FAIL:-1}"
fi

echo $((EVM_INIT_X509 | EVM_SETUP_COMPLETE)) > "${SECURITYFS_MNT}/evm"
printf "  Configuring EVM to enforce signatures: "
"${BUSYBOX}" cat "${SECURITYFS_MNT}/evm" ; echo

if ! "${TESTFILE}"; then
  echo " Error: Could not run ${TESTFILE}"
  exit_test "${FAIL:-1}"
fi

log_modebits=$((0100755))
for prg in "${TESTFILE}" "${BUSYBOX}" "$(which getfattr)"; do
  evmxattr=$(getfattr -m ^security -e hex --dump "${prg}" 2>/dev/null |
    sed -n 's/^security.evm=0x\(.*\)/\1/p')
  fn=$(basename "${prg}")
  printf " Checking for ${fn} in log: "
  measurementlog_find "${SECURITYFS_MNT}" "^10 .* evm-sig sha256:.* .*/${fn} ${evmxattr} security.ima [[:xdigit:]]+ .* 0 0 ${log_modebits}" 1
  printf "Done\n"
done

measurementlog_find "${SECURITYFS_MNT}" "^10 .* evm-sig .* .* .*\s+0 0 ${log_modebits}$" 3

# Modify mode bits to prevent it from running
chmod 777 "${TESTFILE}"
if "${TESTFILE}" 2>/dev/null; then
  echo " Error: Could run ${TESTFILE} even though it must not be possible."
  exit_test "${FAIL:-1}"
fi

# Restore mode bits to allow running again
chmod "${modebits}" "${TESTFILE}"
if ! "${TESTFILE}" 2>/dev/null; then
  echo " Error: Could not run ${TESTFILE} even though it must be possible again."
  exit_test "${FAIL:-1}"
fi

measurementlog_find "${SECURITYFS_MNT}" "^10 .* evm-sig .* .* .*\s+0 0 ${log_modebits}$" 3

exit_test "${SUCCESS:-0}"
