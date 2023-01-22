#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3043,SC3057
# set -x

get_hash_algo_strings()
{
  local flags="${1}"

  local algos=""

  [ $((flags & 1)) -ne 0 ] && algos="${algos},sha256"
  [ $((flags & 2)) -ne 0 ] && algos="${algos},sha384"
  [ $((flags & 4)) -ne 0 ] && algos="${algos},sha512"

  # remove leading ,
  [ "${algos:0:1}" = "," ] && algos="${algos:1}"
  echo "${algos}"
}

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

G_ALGOS=${G_ALGOS:-1}
KEY=./rsakey.pem

algos_str=$(get_hash_algo_strings "${G_ALGOS}")
[ -z "${algos_str}" ] && exit "${SUCCESS:-0}"

policy="appraise func=SETXATTR_CHECK appraise_algos=${algos_str} \n"

set_appraisal_policy_from_string "${SECURITYFS_MNT}" "${policy}" "" 1

echo > testfile
algo=1
while [ "${algo}" -le 4 ]; do
  pass=0
  algo_str=$(get_hash_algo_strings "${algo}")

  evmctl ima_sign --imasig --key "${KEY}" -a "${algo_str}" testfile 1>/dev/null 2>&1 && pass=1

  # if algo is a bit set in G_ALGOS, then the test must pass, since algo is in policy
  mustpass=$((G_ALGOS & algo))
  case "${pass}" in
  0)
    case "${mustpass}" in
    0)
      # echo " GOOD: Could not sign file with hash ${algo_str} since not in ${algos_str}"
      ;;
    *)
      echo " Error: Could not write xattr for file signed with hash ${algo_str} even though it should be possible"
      echo " policy: |${policy}|"
      exit "${FAIL:-1}"
      ;;
    esac
    ;;
  1)
    case "${mustpass}" in
    0)
      echo " Error: Could write xattr for file signed with hash ${algo_str} even though it should NOT be possible"
      echo " policy: |${policy}|"
      exit "${FAIL:-1}"
      ;;
    *)
      # echo " GOOD: Could sign file with hash ${algo_str} since it is in ${algos_str}"
      ;;
    esac
    ;;
  esac
  algo=$((algo * 2))
done

exit "${SUCCESS:-0}"
