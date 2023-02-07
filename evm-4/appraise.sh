#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3043,SC3045

. ./ns-common.sh

# Two local test functions
check_busybox2_not_running() {
  local msg="$1"

  if busybox2 cat "${SECURITYFS_MNT}/ima/policy" >/dev/null 2>&1; then
    echo " Error: Could execute busybox2 ${msg}"
    exit_test "${FAIL:-1}"
  fi
}

check_busybox2_running() {
  local msg="$1"

  if ! busybox2 cat "${SECURITYFS_MNT}/ima/policy" >/dev/null 2>&1; then
    echo " Error: Could NOT execute busybox2 ${msg}"
    exit_test "${FAIL:-1}"
  fi
}

mnt_securityfs "${SECURITYFS_MNT}"

KEY=./rsakey.pem
CERT=./rsa.crt

keyctl newring _ima @s >/dev/null 2>&1
keyctl newring _evm @s >/dev/null 2>&1

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

# Availability of evm_xattrs depends on CONFIG_EVM_ADD_XATTRS=y
if [ -f "${SECURITYFS_MNT}/integrity/evm/evm_xattrs" ]; then
  if ! printf "security.test" > "${SECURITYFS_MNT}/integrity/evm/evm_xattrs"; then
    echo " Error: Could not write security.test to ${SECURITYFS_MNT}/integrity/evm/evm_xattrs"
    exit_test "${FAIL:-1}"
  fi
  if ! printf "." > "${SECURITYFS_MNT}/integrity/evm/evm_xattrs"; then
    echo " Error: Could not write '.' to ${SECURITYFS_MNT}/integrity/evm/evm_xattrs"
    exit_test "${FAIL:-1}"
  fi
  if printf "security.test2" > "${SECURITYFS_MNT}/integrity/evm/evm_xattrs"; then
    echo " Error: Could write security.test2 to ${SECURITYFS_MNT}/integrity/evm/evm_xattrs after writing '.'"
    exit_test "${FAIL:-1}"
  fi
  if ! grep -q "security.test" "${SECURITYFS_MNT}/integrity/evm/evm_xattrs"; then
    echo " Error: security.test is not listed in ${SECURITYFS_MNT}/integrity/evm/evm_xattrs"
    cat "${SECURITYFS_MNT}/integrity/evm/evm_xattrs"
    exit_test "${FAIL:-1}"
  fi
fi

# To be able to write security.evm set EVM_ALLOW_METADATA flag
echo $((EVM_ALLOW_METADATA_WRITES)) > "${SECURITYFS_MNT}/evm"
printf "  Configuring EVM with EVM_ALLOW_METADATA_WRITES flag: "
cat "${SECURITYFS_MNT}/evm" ; echo

# Sign tools to be able to use them later on
for t in getfattr setfattr evmctl setcap; do
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
check_busybox2_not_running "without signature even though appraise policy is active"

if ! err=$(evmctl sign --imasig --portable --key "${KEY}" -a sha256 "$(which busybox2)" 2>&1); then
  echo " Error: Could not sign busybox2: ${err}"
  exit_test "${FAIL:-1}"
fi
if ! err=$(evmctl sign --imasig --portable --key "${KEY}" -a sha256 "$(which busybox)"  2>&1); then
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

# Enable enforcement of metadata
echo $((EVM_INIT_X509)) > "${SECURITYFS_MNT}/evm"
printf "  Configuring EVM with EVM_INIT_X509 flag: "
cat "${SECURITYFS_MNT}/evm" ; echo

# Add security.capability to it, which now must prevent busybox2 from running since
# signature does not cover this xattr
setcap cap_kill+eip "$(type -P busybox2)"
if [ -z "$(getfattr -m ^security.capability -e hex --dump "$(type -P busybox2)" 2>/dev/null)" ]; then
  echo " Error: cap_kill capability was not set on busybox2"
  exit_test "${FAIL:-1}"
fi

# Using busybox2 must NOT work since security.capability was added
check_busybox2_not_running "after security.capability was added"

# Remove security.capability
if ! setfattr -x security.capability "$(type -P busybox2)"; then
  echo " Error: Removing security.capability must work"
  exit_test "${FAIL:-1}"
fi

# Using busybox2 must work since security.capability was removed
check_busybox2_running "after removing security.capability"

# change mode on the file
busybox chmod o=w "$(type -P busybox2)"

# Using busybox2 must NOT work since mode was changed
check_busybox2_not_running "after security.capability was added"

# change back mode on file
busybox chmod o=rx "$(type -P busybox2)"

# Using busybox2 must work again since mode was reverted
check_busybox2_running "after removing security.capability"

if [ -f "${SECURITYFS_MNT}/integrity/evm/evm_xattrs" ]; then
  if ! setfattr -n "security.test" -v "0x050204" "$(type -P busybox2)"; then
    echo " Error: Could not set security.test special security xattr"
    exit_test "${FAIL:-1}"
  fi

  check_busybox2_not_running "after security.test was added"

  # Remove security.capability
  if ! setfattr -x security.test "$(type -P busybox2)"; then
    echo " Error: Removing security.test must work"
    exit_test "${FAIL:-1}"
  fi

  check_busybox2_running "after security.test was removed"
fi

if ! setfattr -n "security.foo" -v "0x050204" "$(type -P busybox2)"; then
  echo " Error: Could not set security.foo special security xattr"
  exit_test "${FAIL:-1}"
fi

# Using busybox2 must work since security.foo is of no relevance
check_busybox2_running "after setting security.foo"

# A bad EVM signature (unknown key) that must not allow the file to execute anymore
EVMSIG="0x050204f55d1ddc01007edb34de4276aa03ff00de1f1d3510f4f96310a6a03a3f1e526a211db6746d95e66f5eca1b4165a50d0cd9a70866ee531bde43164a35c27e18c3cc22203d6fb99162017318d73700210aa9b55668b111a66915650bfc6be50f4697145d87249d71c86b851a3c592b28e6f2b5a736d64c020c2131591b003c7633fcbc9de9dc15486cc7a32256bade1f68eb10cee77fd01dc0dc549ba1b90187368619bf36beac7669a674c022471ac8b271acccd182db9f468cd671d1b2c780dbbc9eddf41d44d20fb4f341a4fd32dedc1082db9e14eba320954fe147d0638cb90a11161aa0dc2e22eb89a0623db4058cf5fe0458245db7d0626b2d71f8fe13139240431c21e9"
if ! setfattr -n security.evm -v "${EVMSIG}" "$(type -P busybox2)"; then
  echo " Error: Setting security.evm must work"
  exit_test "${FAIL:-1}"
fi

# Using busybox2 must not work since the EVM signature is bad
check_busybox2_not_running "with bad EVM signature"

# Remove both signatures
setfattr -x security.evm "$(type -P busybox2)"
if ! setfattr -x security.ima "$(type -P busybox2)"; then
  echo " Error: Removing security.ima must work"
  exit_test "${FAIL:-1}"
fi

# Using busybox2 must not work anymore since it's completely unsigned
check_busybox2_not_running "after removing security.ima"

exit_test "${SUCCESS:-0}"
