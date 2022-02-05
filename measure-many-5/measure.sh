#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3043

# Caller must pass:
# NSID: distinct namespace id number
# FAILFILE: name of file to create upon failure
# NUM_CONTAINERS: number of containers running

# Get a hash name given a number's lowest 2 bits
# Use only sha1, sha256, sha512 that busybox likely supports
get_hash()
{
  local id="${1}"

  local h

  case "$((id & 3))" in
  0) h="sha1";;
  1) h="sha256";;
  2) h="sha512";;
  3) h="sha256";;
  esac

  echo "${h}"
}

# Get a template name given a number's bits 2,3
# Don't use the old 'ima' template since it doesn't support
# many hashes
get_template()
{
  local id="${1}"

  local t

  case "$(((id >> 2) & 3))" in
  0) t="ima-ng";;
  1) t="ima-buf";;
  2) t="ima-sig";;
  3) t="ima-modsig";;
  esac

  echo "${t}"
}

create_ima_ns()
{
  local mntdir="${1}"
  local hash_algo="${2}"
  local template="${3}"

  local msg

  if ! msg=$(mount -t securityfs "${mntdir}" "${mntdir}" 2>&1); then
    echo " Error: Could not mount securityfs: ${msg}"
    return "${SKIP:-3}"
  fi

  if [ ! -f "${mntdir}/ima/hash" ]; then
    echo " Error: Missing hash file in IMA's securityfs"
    return "${SKIP:-3}"
  fi

  if [ ! -f "${mntdir}/ima/template_name" ]; then
    echo " Error: Missing template file in IMA's securityfs"
    return "${SKIP:-3}"
  fi

  if ! echo "${hash_algo}" > "${mntdir}/ima/hash"; then
    echo " Error: Could not write '${hash_algo}' to IMA securityfs file"
    return "${FAIL:-1}"
  fi

  if ! echo "${template}" > "${mntdir}/ima/template_name"; then
    echo " Error: Could not write '${template}' to IMA securityfs file"
    return "${FAIL:-1}"
  fi

  if ! echo "1" > "${mntdir}/ima/active"; then
    echo " Error: Could not activate IMA namespace"
    echo " hash:     ${hash_algo}"
    echo " template: ${template}"
    return "${FAIL:-1}"
  fi

  return "${SUCCESS:-0}"
}

. ./ns-common.sh

testfile="testfile"
bakfile="bakfile"
cmdfile="cmdfile"
mntdir="/mnt"

stage=0
while [ "${stage}" -le 6 ]; do
  syncfile="syncfile-${stage}"
  cmdfile="cmdfile-${stage}"

  if [ "$NSID" -eq "0" ]; then
    # coordinator NSID==0 tells other containers what to do
    wait_cage_full "${NSID}" "${syncfile}" "${NUM_CONTAINERS}"

    echo "At stage: ${stage}"
    case "${stage}" in
    0) cmd="create-ima-ns";;
    1) cmd="set-policy";;
    2) cmd="execute-hash-check"
       printf "/bin/env sh\necho a" >> "${testfile}"
       chmod 755 "${testfile}"
       ;;
    3|4) cmd="execute-hash-check"
       echo "b" >> "${testfile}"
       ;;
    5) cp "${testfile}" "${bakfile}"
       rm "${testfile}"
       mv "${bakfile}" "${testfile}"
       cmd="execute-hash-check"
       echo "b" >> "${testfile}"
       ;;
    esac

    printf "${cmd}" > "${cmdfile}"

    # let the containers out of the cage
    open_cage "${syncfile}"
  else
    wait_in_cage "${NSID}" "${syncfile}"

    case "$(cat "${cmdfile}")" in
    create-ima-ns)
      hash_algo=$(get_hash "${NSID}")
      template=$(get_template "${NSID}")
      if ! create_ima_ns "${mntdir}" "${hash_algo}" "${template}"; then
        echo " Error: Could not create IMA-ns and configure hash '${hash_algo}' and template '${template}'"
        echo > "${FAILFILE}"
      fi
      ;;
    set-policy)
      echo "measure func=BPRM_CHECK mask=MAY_EXEC " > "${mntdir}/ima/policy"
      ;;
    execute-hash-check)
      ./"${testfile}" 1>/dev/null 2>&1
      filehash=$(hash_file "${hash_algo}" "${testfile}")
      num=$(grep -c "${filehash}" "${mntdir}/ima/ascii_runtime_measurements")
      if [ "${num}" -ne 1 ]; then
        echo " Error: Could not find ${hash_algo} '${filehash}' in IMA log"
        grep "${testfile}" "${mntdir}/ima/ascii_runtime_measurements"
        echo > "${FAILFILE}"
      fi
      ;;
    esac
  fi

  stage=$((stage + 1))
done

exit "${SUCCESS:-0}"
