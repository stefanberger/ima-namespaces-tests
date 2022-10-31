#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3043,SC3028

#set -x

# Caller must pass
# NSID: distinct namespace id number
# FAILFILE: name of file to create upon failure
# NUM_CONTAINERS: The number of containers started
NSID=${NSID:-0}
FAILFILE=${FAILFILE:-failfile}

load_key()
{
  local cert="$1"

  keyctl padd asymmetric "" %keyring:_ima < "${cert}" || echo > "${FAILFILE}"
}

load_policy()
{
  local policy

  policy='measure func=KEY_CHECK \n'\
'appraise func=SETXATTR_CHECK appraise_algos=sha256,sha512 \n'\
'appraise func=BPRM_CHECK mask=MAY_EXEC uid=0 gid=0 fowner=0 fgroup=0 \n'\
'measure func=BPRM_CHECK mask=MAY_EXEC uid=0 gid=0 fowner=0 fgroup=0 \n'

  set_appraisal_policy_from_string "${SECURITYFS_MNT}" "${policy}" "${FAILFILE}" 1
}

create_own_key()
{
  local keyfile="${1}"
  local certfile="${2}"
  local id="${3}"

  local destdir msg

  destdir=$(dirname "${keyfile}")
  if ! mkdir -p "${destdir}"; then
    echo " Error: Could not created directory ${destdir} in namespace"
    echo > "${FAILFILE}"
    return
  fi

  if ! msg=$(openssl req \
                -config "${CONFIG_FILE}" \
                -extensions usr_cert \
                -x509 \
                -sha256 \
                -newkey rsa \
                -keyout "${keyfile}" \
                -days 365 \
                -subj "/CN=test-${id}" \
                -nodes \
                -outform der \
                -out "${certfile}" 2>&1); then
    echo " Error: Could not create key in namespace"
    echo "${msg}"
    echo > "${FAILFILE}"
    return
  fi

  # Sanity check
  msg=$(openssl x509 -inform der -in "${certfile}" -text | grep "X509v3 Subject Key Identifier")
  if [ -z "${msg}" ]; then
    echo " Error: Missing Subject Key Idenitfier in created cert"
    echo > "${FAILFILE}"
  fi
}

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

KEY=./rsakey.pem
CERT=./rsa.crt
KEY2=./rsakey2.pem
BUSYBOX2="$(which busybox2)"
CONFIG_FILE=skid.conf

# Directory where each namespace will store its own key into
mydir="mydir-${NSID}"
own_key="${mydir}/ownrsakey.pem"
own_cert="${mydir}/ownrsa.crt"
own_busybox2="${mydir}/busybox2"

if [ "${NSID}" -eq 0 ]; then
  evmctl ima_sign --imasig --key "${KEY}" -a sha256 "$(which busybox)"  >/dev/null 2>&1
  evmctl ima_sign --imasig --key "${KEY}" -a sha256 "$(which keyctl)"   >/dev/null 2>&1
  evmctl ima_sign --imasig --key "${KEY}" -a sha256 "$(which evmctl)"   >/dev/null 2>&1
  evmctl ima_sign --imasig --key "${KEY}" -a sha256 "$(which openssl)"  >/dev/null 2>&1
fi

stage="0"

while [ "${stage}" -le 14 ]; do
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
       if ! msg=$(evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${BUSYBOX2}" 2>&1); then
         echo " Error: Could not sign ${BUSYBOX2} with ${KEY}"
         echo "${msg}"
         echo > "${FAILFILE}"
       fi
       ;;
    5) cmd="execute-fail"   # modified busybox2 must fail to run
       echo >> "${BUSYBOX2}"
       ;;
    6) cmd="execute-pass"   # now that it's signed, it must run
       if ! msg=$(evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${BUSYBOX2}" 2>&1); then
         echo " Error: Could not sign ${BUSYBOX2} with ${KEY}"
         echo "${msg}"
         echo > "${FAILFILE}"
       fi
       ;;
    7) cmd="execute-fail"   # now that it's signed with an unknown key, it must fail
       if ! msg=$(evmctl ima_sign --imasig --key "${KEY2}" -a sha256 "${BUSYBOX2}" 2>&1); then
         echo " Error: Could not sign ${BUSYBOX2} with ${KEY2}"
         echo "${msg}"
         echo > "${FAILFILE}"
       fi
       ;;
    8) cmd="create-own-key";; # create own key
    9) cmd="load-own-key";;   # load own key now
    10) cmd="copy-modify-busybox2";; # have them copy and modify busybox2 but not sign it
    11) cmd="execute-fail-own-busybox2";; # own busybox2 execution must fail
    12) cmd="sign-own-busybox2-sha1-fail";; # sign own busybox2 with own key but not-allowed sha1
    13) cmd="sign-own-busybox2";; # sign own busybox2 with own key but not-allowed sha1
    14) cmd="execute-pass-own-busybox2";; # own busybox2 execution must pass now
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
    create-own-key)
       create_own_key "${own_key}" "${own_cert}" "${NSID}"
       ;;
    load-own-key)
      load_key "${own_cert}" >/dev/null
      ctr=$(grep -c " _ima " "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
      if [ "${ctr}" -ne 1 ]; then
        echo " Error: Expected to find key in measurement list."
        echo > "${FAILFILE}"
      fi
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
      expected="123"
      if ! msg=$("${BUSYBOX2}" echo "${expected}") 2>/dev/null; then
        echo " Error: Could not execute signed ${BUSYBOX2}"
        echo > "${FAILFILE}"
      fi
      if [ "${msg}" != "${expected}" ]; then
        echo " Error: msg variable does not have expected value"
        echo " expected: ${expected}"
        echo " actual  : ${msg}"
        echo > "${FAILFILE}"
      fi
      ;;
    copy-modify-busybox2)
      cp "${BUSYBOX2}" "${own_busybox2}"
      echo "${RANDOM}" >> "${own_busybox2}"
      ;;
    sign-own-busybox2)
      if ! msg=$(evmctl ima_sign --imasig --key "${own_key}" -a sha256 "${own_busybox2}" 2>&1); then
        echo " Error: Could not sign ${own_busybox2} with own key ${own_key}"
        echo " ${msg}"
        echo > "${FAILFILE}"
      fi
      ;;
    sign-own-busybox2-sha1-fail)
      if msg=$(evmctl ima_sign --imasig --key "${own_key}" -a sha1 "${own_busybox2}" 2>&1); then
        echo " Error: Could sign ${own_busybox2} with own key ${own_key} and sha1 even though sha1 is not allowed"
        echo " ${msg}"
        echo > "${FAILFILE}"
      fi
      ;;
    execute-fail-own-busybox2)
      if "${own_busybox2}" echo >/dev/null 2>/dev/null; then
        echo " Error: Could execute unsigned/not properly signed ${own_busybox2}"
        echo > "${FAILFILE}"
      fi
      ;;
    execute-pass-own-busybox2)
      expected="123"
      if ! msg=$("${own_busybox2}" echo "${expected}") 2>/dev/null; then
        echo " Error: Could not execute signed ${own_busybox2}"
        echo > "${FAILFILE}"
      fi
      if [ "${msg}" != "${expected}" ]; then
        echo " Error: msg variable does not have expected value"
        echo " expected: ${expected}"
        echo " actual  : ${msg}"
        echo > "${FAILFILE}"
      fi
      ;;
    *)
      echo " Unknown command: $(cat ${cmdfile})"
      echo > "${FAILFILE}"
    esac
  fi

  stage=$((stage + 1))
done

exit "${SUCCESS:-0}"
