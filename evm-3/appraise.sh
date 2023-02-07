#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3045

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

KEY=./rsakey.pem
CERT=./rsa.crt

keyctl newring _ima @s >/dev/null 2>&1
keyctl newring _evm @s >/dev/null 2>&1

BUSYBOX2=$(which busybox2)
BUSYBOX=$(which busybox)

prepolicy1="measure func=KEY_CHECK keyrings=_evm|_ima \n"
printf "${prepolicy1}" > "${SECURITYFS_MNT}/ima/policy" || {
  echo " Error: Could not set key measurement policy."
  exit_test "${FAIL:-1}"
}

if ! err=$(keyctl padd asymmetric "" %keyring:_ima < "${CERT}" 2>&1); then
  echo " Error: Could not load key onto _ima keyring: ${err}"
  exit_test "${FAIL:-1}"
fi
if ! err=$(keyctl padd asymmetric "" %keyring:_evm < "${CERT}" 2>&1); then
  echo " Error: Could not load key onto _evm keyring: ${err}"
  exit_test "${FAIL:-1}"
fi

# Expecting measurement of both keys
ctr=$(grep -c -E " _(ima|evm) " "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
exp=2
if [ "${ctr}" -ne "${exp}" ]; then
  echo " Error: Expected ${exp} measurements of keys in container's measurement list, but found ${ctr}."
  exit_test "${FAIL:-1}"
fi

# To be able to write security.evm set EVM_ALLOW_METADATA flag
echo $((EVM_ALLOW_METADATA_WRITES)) > "${SECURITYFS_MNT}/evm"
printf "  Configuring EVM with EVM_ALLOW_METADATA_WRITES flag: "
cat "${SECURITYFS_MNT}/evm" ; echo

# Sign tools to be able to use them later on
for t in getfattr setfattr evmctl; do
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
'measure func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'

if ! printf "${policy}" > "${SECURITYFS_MNT}/ima/policy"; then
  echo " Error: Could not set appraise policy. Does IMA-ns support IMA-appraise?"
  exit_test "${FAIL:-1}"
fi

# Using busybox2 must fail since it's not signed
if busybox2 cat "${SECURITYFS_MNT}/ima/policy" >/dev/null 2>&1; then
  echo " Error: Could execute unsigned busybox2 even though appraise policy is active"
  exit_test "${FAIL:-1}"
fi

if ! err=$(evmctl sign --imasig --portable --key "${KEY}" -a sha256 "${BUSYBOX2}" 2>&1); then
  echo " Error: Could not sign busybox2: ${err}"
  exit_test "${FAIL:-1}"
fi
if ! err=$(evmctl sign --imasig --portable --key "${KEY}" -a sha256 "${BUSYBOX}"  2>&1); then
  echo " Error: Could not sign busybox: ${err}"
  exit_test "${FAIL:-1}"
fi

template=$(get_template_from_log "${SECURITYFS_MNT}")
case "${template}" in
ima-sig|ima-ns) num_extra=1;;
*) num_extra=0;;
esac

before=$(grep -c busybox2 "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")

nspolicy=$(busybox2 cat "${SECURITYFS_MNT}/ima/policy")
policy="${prepolicy1}${policy}"
if [ "$(printf "${policy}")" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: |$(printf "${policy}")|"
  echo "actual  : |${nspolicy}|"
  exit_test "${FAIL:-1}"
fi

after=$(grep -c busybox2 "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
expected=$((before + num_extra))
if [ "${expected}" -ne "${after}" ]; then
  echo " Error: Could not find ${expected} measurement of busybox2 in container, found ${after}."
  exit_test "${FAIL:-1}"
fi

if ! evmsig="$(getfattr -m ^security.evm -e hex --dump "${BUSYBOX2}" 2>/dev/null |
              sed  -n 's/^security.evm=//p')"; then
  echo " Error: Could not get EVM sigature from ${BUSYBOX2}"
  exit_test "${FAIL:-1}"
fi

# Remove security.evm
if ! setfattr -x security.evm "${BUSYBOX2}"; then
  echo " Error: Removing security.evm must work"
  exit_test "${FAIL:-1}"
fi

# Using busybox2 must still work since it's still signed with IMA signature
if ! busybox2 cat "${SECURITYFS_MNT}/ima/policy" >/dev/null 2>&1; then
  echo " Error: Could not execute "
  exit_test "${FAIL:-1}"
fi

echo $((EVM_INIT_X509)) > "${SECURITYFS_MNT}/evm"
printf "  Configuring EVM with EVM_INIT_X509 flag: "
cat "${SECURITYFS_MNT}/evm" ; echo

# Using busybox2 must still work since it's still signed with IMA signature
if ! busybox2 cat "${SECURITYFS_MNT}/ima/policy" >/dev/null 2>&1; then
  echo " Error: Could not execute busybox2"
  exit_test "${FAIL:-1}"
fi

# Apply previously read EVM signature now
if ! setfattr -n security.evm -v "${evmsig}" "${BUSYBOX2}"; then
  echo " Error: Setting security.evm must work"
  exit_test "${FAIL:-1}"
fi

# Using busybox2 must still work since its now signed with good EVM signature
if ! busybox2 cat "${SECURITYFS_MNT}/ima/policy" >/dev/null 2>&1; then
  echo " Error: Could not execute busybox2"
  exit_test "${FAIL:-1}"
fi

# A bad EVM signature (unknown key) that must not allow the file to execute anymore
EVMSIG="0x050204f55d1ddc01007edb34de4276aa03ff00de1f1d3510f4f96310a6a03a3f1e526a211db6746d95e66f5eca1b4165a50d0cd9a70866ee531bde43164a35c27e18c3cc22203d6fb99162017318d73700210aa9b55668b111a66915650bfc6be50f4697145d87249d71c86b851a3c592b28e6f2b5a736d64c020c2131591b003c7633fcbc9de9dc15486cc7a32256bade1f68eb10cee77fd01dc0dc549ba1b90187368619bf36beac7669a674c022471ac8b271acccd182db9f468cd671d1b2c780dbbc9eddf41d44d20fb4f341a4fd32dedc1082db9e14eba320954fe147d0638cb90a11161aa0dc2e22eb89a0623db4058cf5fe0458245db7d0626b2d71f8fe13139240431c21e9"
if ! setfattr -n security.evm -v "${EVMSIG}" "${BUSYBOX2}"; then
  echo " Error: Setting security.evm must work"
  exit_test "${FAIL:-1}"
fi

# Using busybox2 must not work since the EVM signature is bad
if busybox2 cat "${SECURITYFS_MNT}/ima/policy" >/dev/null 2>&1; then
  echo " Error: Could execute busybox2 with bad EVM signature"
  getfattr -m ^security.evm -e hex --dump "${BUSYBOX2}"
  exit_test "${FAIL:-1}"
fi

# Remove both signatures
setfattr -x security.evm "${BUSYBOX2}"
if ! setfattr -x security.ima "${BUSYBOX2}"; then
  echo " Error: Removing security.ima must work"
  exit_test "${FAIL:-1}"
fi

# Using busybox2 must not work anymore since it's completely unsigned
if busybox2 cat "${SECURITYFS_MNT}/ima/policy" >/dev/null 2>&1; then
  echo " Error: Could execute unsigned busybox2"
  exit_test "${FAIL:-1}"
fi

exit_test "${SUCCESS:-0}"
