#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause
# set -x

. ./ns-common.sh

# Created this signature using: evmctl sign -a sha256 --portable --key [...]/keys/rsakey.pem <somefile>
EVMSIG="0x050204f55d1ddc01007edb34de4276aa03ff00de1f1d3510f4f96310a6a03a3f1e526a211db6746d95e66f5eca1b4165a50d0cd9a70866ee531bde43164a35c27e18c3cc22203d6fb99162017318d73700210aa9b55668b111a66915650bfc6be50f4697145d87249d71c86b851a3c592b28e6f2b5a736d64c020c2131591b003c7633fcbc9de9dc15486cc7a32256bade1f68eb10cee77fd01dc0dc549ba1b90187368619bf36beac7669a674c022471ac8b271acccd182db9f468cd671d1b2c780dbbc9eddf41d44d20fb4f341a4fd32dedc1082db9e14eba320954fe147d0638cb90a11161aa0dc2e22eb89a0623db4058cf5fe0458245db7d0626b2d71f8fe13139240431c21e9"

# Writing security.evm must fail before IMA namespace is active
for f in good* bad*; do
  if setfattr -n security.evm -v "${EVMSIG}" "${f}" >/dev/null 2>&1 ; then
    echo " Error: Could EVM-sign file ${f} although this MUST NOT be possible before IMA namespace is active!"
    exit "${FAIL:-1}"
  fi
  if setfattr -x security.evm "${f}" >/dev/null 2>&1 ; then
    echo " Error: Could remove security.evm although this MUST NOT be possible before IMA namespace is active!"
    exit "${FAIL:-1}"
  fi
done

mnt_securityfs "${SECURITYFS_MNT}"

# Writing security.evm must fail for as long as EVM_ALLOW_METADATA_WRITES has not been
# written to evm file
for f in good* bad*; do
  if setfattr -n security.evm -v "${EVMSIG}" "${f}" >/dev/null 2>&1 ; then
    echo " Error: Could EVM-sign file ${f} although this MUST NOT be possible before configuring EVM!"
    exit "${FAIL:-1}"
  fi
  if setfattr -x security.evm "${f}" >/dev/null 2>&1 ; then
    echo " Error: Could remove security.evm although this MUST NOT be possible before configuring EVM!"
    exit "${FAIL:-1}"
  fi
done

echo $((EVM_SETUP_COMPLETE | EVM_ALLOW_METADATA_WRITES)) > "${SECURITYFS_MNT}/evm"
printf "  Configuring EVM with EVM_ALLOW_METADATA_WRITES flag: "
cat "${SECURITYFS_MNT}/evm" && echo

for f in good*; do
  if ! setfattr -n security.evm -v "${EVMSIG}" "${f}" >/dev/null 2>&1 ; then
    echo " Error: Could not EVM-sign file ${f} although this MUST be possible after configuring EVM!"
    exit "${FAIL:-1}"
  fi
  if ! setfattr -x security.evm "${f}" >/dev/null 2>&1 ; then
    echo " Error: Could not remove security.evm from file ${f} although this MUST be possible after configuring EVM!"
    exit "${FAIL:-1}"
  fi
done

for f in bad*; do
  if setfattr -n security.evm -v "${EVMSIG}" "${f}" >/dev/null 2>&1 ; then
    echo " Error: Could EVM-sign file ${f} although this MUST NOT be possible"
    exit "${FAIL:-1}"
  fi
  if setfattr -x security.evm -v "${f}" >/dev/null 2>&1 ; then
    echo " Error: Could remove security.evm from file ${f} although this MUST NOT be possible"
    exit "${FAIL:-1}"
  fi
done

exit "${SUCCESS:-0}"
