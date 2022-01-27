#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3043

#set -x

# Caller must pass
# NSID: distinct namespace id number
# FAILFILE: name of file to create upon failure
# NUM_CONTAINERS: The number of containers started

load_key()
{
  local cert="$1"

  keyctl padd asymmetric "" %keyring:_ima < "${cert}" || echo > "${FAILFILE}"
}

unload_key()
{
  local keyid="$1"

  keyctl unlink "${keyid}" %keyring:_ima || echo > "${FAILFILE}"
}

load_policy()
{
  local policy

  policy='measure func=KEY_CHECK \n'\
'appraise func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'\
'measure func=BPRM_CHECK mask=MAY_EXEC uid=0 \n'
  printf "${policy}" > /mnt/ima/policy || {
    echo " Error: Could not set appraise policy. Does IMA-ns support IMA-appraisal?"
  }
}

. ./ns-common.sh

mnt_securityfs "/mnt"

KEY=./rsakey.pem
CERT=./rsa.crt
KEY2=./rsakey2.pem
CERT2=./rsa2.crt

if [ "${NSID}" -eq 0 ]; then
  evmctl ima_sign --imasig --key "${KEY}" -a sha256 "$(which busybox)"  >/dev/null 2>&1
  evmctl ima_sign --imasig --key "${KEY}" -a sha256 "$(which keyctl)"  >/dev/null 2>&1
fi

stage="0"

while [ "${stage}" -le 13 ]; do
  syncfile="syncfile-${stage}"
  cmdfile="cmdfile-${stage}"

  if [ "${NSID}" -eq "0" ]; then
    # coordinator NSID==0 tells other containers what to do
    wait_cage_full "${NSID}" "${syncfile}" "${NUM_CONTAINERS}"

    echo "At stage: ${stage}"
    case "${stage}" in
    0) cmd="ima-keyring";;
    1) cmd="load-key1";;
    2) cmd="load-policy";;
    3) cmd="execute-fail";; # running busybox2 must fail
    4) cmd="execute-pass"   # now that it's signed, it must run
       evmctl ima_sign --imasig --key "${KEY}" -a sha256 "$(which busybox2)"  >/dev/null 2>&1
       ;;
    5) cmd="execute-fail"   # modified busybox2 must fail to run
       echo >> "$(which busybox2)"
       ;;
    6) cmd="execute-pass"   # now that it's signed, it must run
       evmctl ima_sign --imasig --key "${KEY}" -a sha256 "$(which busybox2)"  >/dev/null 2>&1
       ;;
    7) cmd="execute-fail"   # now that it's signed with an unknown key, it must fail
       evmctl ima_sign --imasig --key "${KEY2}" -a sha256 "$(which busybox2)"  >/dev/null 2>&1
       ;;
    8) cmd="load-key2";;    # load unknown key now
    9) cmd="execute-pass";; # with 2nd key loaded it must pass
    10) cmd="execute-fail"  # after modification it must fail again
        echo >> "$(which busybox2)"
        ;;
    11) cmd="execute-pass"  # after re-signing it must pass
        evmctl ima_sign --imasig --key "${KEY}" -a sha256 "$(which busybox2)"  >/dev/null 2>&1
        ;;
    12) cmd="unload-key2"
        ;;
    13) cmd="execute-fail";; # running busybox2 must fail with unknown (=unloaded) key
    esac

    printf "${cmd}" > "${cmdfile}"

    open_cage "${syncfile}"
  else
    wait_in_cage "${NSID}" "${syncfile}"

    case "$(cat "${cmdfile}")" in
    ima-keyring)
      keyctl newring _ima @s >/dev/null 2>&1
      ;;
    load-key1)
      load_key "${CERT}" >/dev/null
      ;;
    load-key2)
      key2=$(load_key "${CERT2}")
      ctr=$(grep -c " _ima " /mnt/ima/ascii_runtime_measurements)
      if [ "${ctr}" -ne 1 ]; then
        echo "Error: Expected to find key in measurement list."
        echo > "${FAILFILE}"
      fi
      ;;
    unload-key2)
      unload_key "${key2}"
      ;;
    load-policy)
      load_policy
      ;;
    execute-fail)
      if "${BUSYBOX2}" echo >/dev/null 2>/dev/null; then
        echo " Error: Could execute unsigned/not properly signed ${BUSYBOX2}"
        echo > "${FAILFILE}"
      fi
      ;;
    execute-pass)
      if "${BUSYBOX2}" echo >/dev/null 2>/dev/null; then
        echo " Error: Could not execute signed ${BUSYBOX2}"
        echo > "${FAILFILE}"
      fi
      ;;
    esac
  fi

  stage=$((stage + 1))
done

exit "${SUCCESS:-0}"
