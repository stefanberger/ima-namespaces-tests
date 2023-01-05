#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3045
#set -x
FAILFILE=${FAILFILE:-failfile}

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

KEY=./rsakey.pem
CERT=./rsa.crt

keyctl newring _ima @s >/dev/null 2>&1
keyctl newring _evm @s >/dev/null 2>&1

prepolicy1="measure func=KEY_CHECK keyrings=_evm|_ima \n"
printf "${prepolicy1}" > "${SECURITYFS_MNT}/ima/policy" || {
  echo " Error: Could not set key measurement policy."
  exit "${FAIL:-1}"
}

# Each namespace needs its own busybox2 test file
NSID=${NSID:-1} # for shellcheck
BUSYBOX2="$(which busybox2)-${NSID}"
cp "$(which busybox2)" "${BUSYBOX2}"

for keyring in _ima _evm; do
  if ! keyctl padd asymmetric "" "%keyring:${keyring}" < "${CERT}" >/dev/null 2>&1; then
    echo " Error: Could not load key onto ${keyring} keyring likley due to key quota restrictions"
    echo > "${FAILFILE}"
    exit "${FAIL:-1}"
  fi
done

# Expecting measurement of both keys
ctr=$(grep -c -E " _(ima|evm) " "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
exp=2
if [ "${ctr}" -ne "${exp}" ]; then
  echo " Error: Expected ${exp} measurements of keys in container's measurement list, but found ${ctr}."
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

# To be able to write security.evm set EVM_ALLOW_METADATA flag
echo $((EVM_ALLOW_METADATA_WRITES)) > "${SECURITYFS_MNT}/evm"
val=$(cat "${SECURITYFS_MNT}/evm")
exp=${EVM_ALLOW_METADATA_WRITES}
if [ "${val}" != "${exp}" ]; then
  echo " Error: Value in evm securityfs is wrong"
  echo " Expected: ${exp}"
  echo " Actual  : ${val}"
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

# Sign tools to be able to use them later on
for t in getfattr setfattr evmctl; do
  tool="$(type -P "${t}")"
  evmctl sign --imasig --portable --key "${KEY}" --uuid -a sha256 "${tool}" >/dev/null 2>&1
  if [ -z "$(getfattr -m ^security.ima -e hex --dump "${tool}" 2>/dev/null)" ]; then
    echo " Error: security.ima should be there now."
    echo > "${FAILFILE}"
    exit "${FAIL:-1}"
  fi
  if [ -z "$(getfattr -m ^security.evm -e hex --dump "${tool}" 2>/dev/null)" ]; then
    echo " Error: security.evm should be there now."
    echo > "${FAILFILE}"
    exit "${FAIL:-1}"
  fi
done

policy='appraise func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'\
'measure func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'

printf "${policy}" > "${SECURITYFS_MNT}/ima/policy" || {
  echo " Error: Could not set appraise policy. Does IMA-ns support IMA-appraise?"
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
}

# Using busybox2 must fail since it's not signed
if ${BUSYBOX2} cat "${SECURITYFS_MNT}/ima/policy" >/dev/null 2>&1; then
  echo " Error: Could execute unsigned ${BUSYBOX2} even though appraise policy is active"
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

evmctl sign --imasig --portable --key "${KEY}" -a sha256 "${BUSYBOX2}"        >/dev/null 2>&1
evmctl sign --imasig --portable --key "${KEY}" -a sha256 "$(type -P busybox)" >/dev/null 2>&1

template=$(get_template_from_log "${SECURITYFS_MNT}")
case "${template}" in
ima-sig|ima-ns) num_extra=1;;
*) num_extra=0;;
esac

before=$(grep -c "${BUSYBOX2}" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")

nspolicy=$(${BUSYBOX2} cat "${SECURITYFS_MNT}/ima/policy")
policy="${prepolicy1}${policy}"
if [ "$(printf "${policy}")" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: |$(printf "${policy}")|"
  echo "actual  : |${nspolicy}|"
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

after=$(grep -c "${BUSYBOX2}" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
expected=$((before + num_extra))
if [ "${expected}" -ne "${after}" ]; then
  echo " Error: Could not find ${expected} measurement of ${BUSYBOX2} in container, found ${after}."
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

# Remove security.evm
if ! setfattr -x security.evm "${BUSYBOX2}"; then
  echo " Error: Removing security.evm must work"
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

# Using busybox2 must still work since it's still signed with IMA signature
if ! ${BUSYBOX2} cat "${SECURITYFS_MNT}/ima/policy" >/dev/null 2>&1; then
  echo " Error: Could not execute "
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

echo $((EVM_INIT_X509)) > "${SECURITYFS_MNT}/evm"
val=$(cat "${SECURITYFS_MNT}/evm")
exp=$((EVM_INIT_X509|EVM_ALLOW_METADATA_WRITES))
if [ "${val}" != "${exp}" ]; then
  echo " Error: Value in evm securityfs is wrong"
  echo " Expected: ${exp}"
  echo " Actual  : ${val}"
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

# A bad EVM signature (unknown key) that must not allow the file to execute anymore
EVMSIG="0x050204f55d1ddc01007edb34de4276aa03ff00de1f1d3510f4f96310a6a03a3f1e526a211db6746d95e66f5eca1b4165a50d0cd9a70866ee531bde43164a35c27e18c3cc22203d6fb99162017318d73700210aa9b55668b111a66915650bfc6be50f4697145d87249d71c86b851a3c592b28e6f2b5a736d64c020c2131591b003c7633fcbc9de9dc15486cc7a32256bade1f68eb10cee77fd01dc0dc549ba1b90187368619bf36beac7669a674c022471ac8b271acccd182db9f468cd671d1b2c780dbbc9eddf41d44d20fb4f341a4fd32dedc1082db9e14eba320954fe147d0638cb90a11161aa0dc2e22eb89a0623db4058cf5fe0458245db7d0626b2d71f8fe13139240431c21e9"
if ! setfattr -n security.evm -v "${EVMSIG}" "${BUSYBOX2}"; then
  echo " Error: Setting security.evm must work"
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

# Using busybox2 must not work since the EVM signature is bad
if ${BUSYBOX2} cat "${SECURITYFS_MNT}/ima/policy" >/dev/null 2>&1; then
  echo " Error: Could execute ${BUSYBOX2} with bad EVM signature"
  getfattr -m ^security.evm -e hex --dump "${BUSYBOX2}"
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

# Remove both signatures
setfattr -x security.evm "${BUSYBOX2}"
if ! setfattr -x security.ima "${BUSYBOX2}"; then
  echo " Error: Removing security.ima must work"
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

# Using busybox2 must not work anymore since it's completely unsigned
if ${BUSYBOX2} cat "${SECURITYFS_MNT}/ima/policy" >/dev/null 2>&1; then
  echo " Error: Could execute unsigned busybox2"
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
