#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3043
#set -x
NSID=${NSID:-0}
SYNCFILE=${SYNCFILE:-syncfile}

. ./ns-common.sh

KEY="/rsakey.pem"
CERT="/rsa.crt"

create_keyring_load_key()
{
  keyctl newring _ima @s >/dev/null 2>&1
  keyctl padd asymmetric "" %keyring:_ima < "${CERT}" >/dev/null 2>&1
}

create_imans()
{
  mnt_securityfs "${SECURITYFS_MNT}"
}

set_policy()
{
  local policy nspolicy

  policy='appraise func=BPRM_CHECK mask=MAY_EXEC uid=0 appraise_type=imasig \n'\
'appraise func=MMAP_CHECK mask=MAY_EXEC uid=0 appraise_type=imasig \n'\
'measure func=BPRM_CHECK mask=MAY_EXEC uid=0 template=ima-ng \n'\
'measure func=MMAP_CHECK mask=MAY_EXEC uid=0 template=ima-sig \n'

  if ! printf "${policy}" > "${SECURITYFS_MNT}/ima/policy"; then
    echo " Error: Could not set appraisal and measurements policy."
    echo > "${FAILFILE}"
  fi

  nspolicy=$(cat "${SECURITYFS_MNT}/ima/policy")
  if [ "$(printf "${policy}")" != "${nspolicy}" ]; then
    echo " Error: Bad policy in namespace."
    echo "expected: |${policy}|"
    echo "actual  : |${nspolicy}|"
    echo > "${FAILFILE}"
  fi
}

sign_files()
{
  local f

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
      echo > "${FAILFILE}"
    fi
  done
}

libimaevm_remove_signature()
{
  local libimaevm

  libimaevm="$(find / 2>/dev/null| grep libimaevm)"

  # Remember signature on libimaevm
  LIBIMAEVM_SIG=$(getfattr -m security.ima -e hex --dump "${libimaevm}" 2>/dev/null |
                  grep "security.ima=" |
                  cut -d"=" -f2)

  # Remove signature from libimaevm
  if ! setfattr -x security.ima "${libimaevm}"; then
    echo " Error: Could not remove security.ima from ${libimaevm}."
    echo > "${FAILFILE}"
  fi
}

libimaevm_restore_signature()
{
  local libimaevm

  libimaevm="$(find / 2>/dev/null| grep libimaevm)"

  # Restore signature
  if ! setfattr -n security.ima -v "${LIBIMAEVM_SIG}" "${libimaevm}"; then
    echo " Error: Could not set security.ima on ${libimaevm}."
    echo > "${FAILFILE}"
  fi
}

# Run evmctl and expect it to work
run_evmctl_success()
{
  if ! evmctl --help >/dev/null; then
    echo " Error: Could not execute evmctl even though evmctl and its libraries are signed"
    echo > "${FAILFILE}"
  fi
}

# Run evmctl and expect it to fail
run_evmctl_failure()
{
  if evmctl --help >/dev/null 2>/dev/null; then
    echo " Error: Could execute evmctl even though libimaevm is not signed anymore"
    echo > "${FAILFILE}"
  fi
}

count_measurements()
{
  local f ctr exp fullpath libimaevm execs

  # setfattr and getfattr are only used by container with NSID=1
  execs="evmctl busybox"
  [ "${NSID}" -eq 1 ] && execs="${execs} setfattr getfattr"

  # Executables are only to be found with template 'ima-ng' and NOT ima-sig
  for f in ${execs}; do
    fullpath="$(which "${f}")"

    # expect 0 log entries with ima-sig
    ctr=$(grep " ima-sig " "${SECURITYFS_MNT}/ima/ascii_runtime_measurements" | grep -c "${fullpath}")
    if [ "${ctr}" -ne 0 ]; then
      echo " Error: ${f} should not have been logged with ima-sig."
      echo > "${FAILFILE}"
      return
    fi

    # expect != 0 log entries with ima-ng
    ctr=$(grep " ima-ng " "${SECURITYFS_MNT}/ima/ascii_runtime_measurements" | grep -c "${fullpath}")
    if [ "${ctr}" -eq 0 ]; then
      echo " Error: ${f} should have been logged with ima-ng."
      echo > "${FAILFILE}"
      return
    fi
  done

  # Libraries are only to be found with template 'ima-sig'
  ctr=$(grep " ima-sig " "${SECURITYFS_MNT}/ima/ascii_runtime_measurements" | grep -c -E "\.so\.")
  if [ "${ctr}" -eq 0 ]; then
    echo " Error: Shared libraries should have been logged with template ima-sig."
    echo > "${FAILFILE}"
    return
  fi
  ctr=$(grep " ima-ng " "${SECURITYFS_MNT}/ima/ascii_runtime_measurements" | grep -c -E "\.so\.")
  if [ "${ctr}" -ne 0 ]; then
    echo " Error: No shared libraries should have been logged with template ima-ng."
    echo > "${FAILFILE}"
    return
  fi

  libimaevm="$(find / 2>/dev/null| grep libimaevm)"

  # There must be 1 entry of libimaevm with signature, 2 in total
  ctr=$(grep " ima-sig " "${SECURITYFS_MNT}/ima/ascii_runtime_measurements" |grep -c -E "${libimaevm} ")
  exp=2
  if [ "${ctr}" -ne "${exp}" ]; then
    echo " Error: Expected ${exp} ima-sig log entries of ${libimaevm} but found ${ctr}."
    echo > "${FAILFILE}"
    return
  fi

  ctr=$(grep " ima-sig " "${SECURITYFS_MNT}/ima/ascii_runtime_measurements" |grep -c -E "${libimaevm} ")
  exp=2
  if [ "${ctr}" -ne "${exp}" ]; then
    echo " Error: Expected ${exp} ima-sig log entries of ${libimaevm} but found ${ctr}."
    echo > "${FAILFILE}"
    return
  fi

  ctr=$(grep " 030204" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements" |grep -c -E "${libimaevm} ")
  exp=1
  if [ "${ctr}" -ne "${exp}" ]; then
    echo " Error: Expected ${exp} ima-sig log entries of ${libimaevm} with signature but found ${ctr}."
    echo > "${FAILFILE}"
    return
  fi
}

stage=1
while [ "${stage}" -le 10 ]; do
  syncfile="syncfile-${stage}"
  cmdfile="cmdfile-${stage}"

  if [ "${NSID}" = "0" ]; then
    # control container
    wait_cage_full 0 "${syncfile}" "${NUM_CONTAINERS}"

    echo "At stage: ${stage}"
    case "${stage}" in
    1) cmd="create-keyring-load-key";;
    2) cmd="create-imans";;
    3) cmd="sign-files";;
    4) cmd="set-policy";;
    5) cmd="run-evmctl-success";;
    6) cmd="libimaevm-remove-signature";;
    7) cmd="run-evmctl-failure";;
    8) cmd="libimaevm-restore-signature";;
    9) cmd="run-evmctl-success";;
    10) cmd="count-measurements";;
    esac

    printf "${cmd}" > "${cmdfile}"
    open_cage "${syncfile}"

  else
    # testing container
    wait_in_cage "${NSID}" "${syncfile}"

    cmd="$(cat "${cmdfile}")"

    case "${cmd}" in
    create-keyring-load-key)     create_keyring_load_key;;
    create-imans)                create_imans;;
    sign-files)                  [ "${NSID}" -eq 1 ] && sign_files;;
    set-policy)                  set_policy;;
    run-evmctl-success)          run_evmctl_success;;
    run-evmctl-failure)          run_evmctl_failure;;
    libimaevm-remove-signature)  [ "${NSID}" -eq 1 ] && libimaevm_remove_signature;;
    libimaevm-restore-signature) [ "${NSID}" -eq 1 ] && libimaevm_restore_signature;;
    count-measurements)          count_measurements;;
    end)                         break;;
    esac
  fi
  stage=$((stage+1))
done
