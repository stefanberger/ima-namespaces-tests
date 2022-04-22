#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059

. ./ns-common.sh

mnt_securityfs "/mnt"

KEY=./rsakey.pem
CERT=./rsa.crt

keyctl newring _ima @s >/dev/null 2>&1
keyctl padd asymmetric "" %keyring:_ima < "${CERT}" >/dev/null 2>&1

# Sign executables we need and all libraries to be able to use executables later on
for f in \
    "$(which evmctl)" \
    "$(which busybox)" \
    "$(which getfattr)" \
    "$(which setfattr)" \
    $(find / 2>/dev/null | grep -E "\.so"); do
  evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${f}" >/dev/null 2>&1
  if [ -z "$(getfattr -m ^security.ima -e hex --dump "${f}" 2>/dev/null)" ]; then
    echo " Error: security.ima should be there now. Is IMA appraisal support enabled?"
    # setting security.ima was only added when appraisal was enable
    exit "${SKIP:-3}"
  fi
done

policy='appraise func=BPRM_CHECK mask=MAY_EXEC appraise_type=imasig uid=0 \n'\
'appraise func=MMAP_CHECK mask=MAY_EXEC uid=0 appraise_type=imasig \n'\
'measure func=BPRM_CHECK mask=MAY_EXEC uid=0 template=ima-ng \n'\
'measure func=MMAP_CHECK mask=MAY_EXEC uid=0 template=ima-sig \n'

printf "${policy}" > /mnt/ima/policy || {
  echo " Error: Could not set appraise policy. Does IMA-ns support IMA-appraise?"
  exit "${SKIP:-3}"
}

# Displaying help screen of evmctl must work
if ! evmctl --help >/dev/null; then
  echo " Error: Could not execute evmctl even though evmctl and its libraries are signed."
  exit "${FAIL:-1}"
fi

libimaevm="$(find / 2>/dev/null| grep libimaevm)"

# Remember signature on libimaevm
libimaevm_sig=$(getfattr -m security.ima -e hex --dump "${libimaevm}" 2>/dev/null |
                grep "security.ima=" |
                cut -d"=" -f2)

# Remove signature from libimaevm
if ! setfattr -x security.ima "${libimaevm}"; then
  echo " Error: Could not remove security.ima on ${libimaevm}."
  exit "${FAIL:-1}"
fi

# Displaying help screen of evmctl must NOT work
if evmctl --help >/dev/null 2>/dev/null; then
  echo " Error: Could execute evmctl even though libimaevm is not signed anymore."
  exit "${FAIL:-1}"
fi

# Restore signature
if ! setfattr -n security.ima -v "${libimaevm_sig}" "${libimaevm}"; then
  echo " Error: Could not set security.ima on ${libimaevm}."
  exit "${FAIL:-1}"
fi

# Displaying help screen of evmctl must work again
if ! evmctl --help >/dev/null; then
  echo " Error: Could not execute evmctl even though libimaevm is signed again."
  exit "${FAIL:-1}"
fi

ctr=$(grep -c "${libimaevm} " /mnt/ima/ascii_runtime_measurements)
exp=2
if [ "${ctr}" -ne "${exp}" ]; then
  echo " Error: Expected ${exp} measurements of ${libimaevm} but found ${ctr}."
  exit "${FAIL:-1}"
fi

# Executables are only to be found with template 'ima-ng' and NOT ima-sig
for f in evmctl busybox setfattr getfattr; do
  fullpath="$(which "${f}")"

  # expect 0 log entries with ima-sig
  ctr=$(grep " ima-sig " /mnt/ima/ascii_runtime_measurements | grep -c "${fullpath}")
  if [ "${ctr}" -ne 0 ]; then
    echo " Error: ${f} should not have been logged with ima-sig."
    exit "${FAIL:-1}"
  fi

  # expect != 0 log entries with ima-ng
  ctr=$(grep " ima-ng " /mnt/ima/ascii_runtime_measurements | grep -c "${fullpath}")
  if [ "${ctr}" -eq 0 ]; then
    echo " Error: ${f} should have been logged with ima-ng."
    exit "${FAIL:-1}"
  fi
done

# Libraries are only to be found with template 'ima-sig'
ctr=$(grep " ima-sig " /mnt/ima/ascii_runtime_measurements | grep -c -E "\.so\.")
if [ "${ctr}" -eq 0 ]; then
  echo " Error: Shared libraries should have been logged with template ima-sig."
  exit "${FAIL:-1}"
fi
ctr=$(grep " ima-ng " /mnt/ima/ascii_runtime_measurements | grep -c -E "\.so\.")
if [ "${ctr}" -ne 0 ]; then
  echo " Error: No shared libraries should have been logged with template ima-ng."
  exit "${FAIL:-1}"
fi

# There must be 1 entry of libimaevm with signature, 2 in total
ctr=$(grep " ima-sig " /mnt/ima/ascii_runtime_measurements |grep -c -E "${libimaevm} ")
exp=2
if [ "${ctr}" -ne "${exp}" ]; then
  echo " Error: Expected ${exp} ima-sig log entries of ${libimaevm} but found ${ctr}."
  exit "${FAIL:-1}"
fi

ctr=$(grep " ima-sig " /mnt/ima/ascii_runtime_measurements |grep -c -E "${libimaevm} ")
exp=2
if [ "${ctr}" -ne "${exp}" ]; then
  echo " Error: Expected ${exp} ima-sig log entries of ${libimaevm} but found ${ctr}."
  exit "${FAIL:-1}"
fi

ctr=$(grep " 030204" /mnt/ima/ascii_runtime_measurements |grep -c -E "${libimaevm} ")
exp=1
if [ "${ctr}" -ne "${exp}" ]; then
  echo " Error: Expected ${exp} ima-sig log entries of ${libimaevm} with signature but found ${ctr}."
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
