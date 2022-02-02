#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC3043

. ./ns-common.sh

# Get a hash name given a number's lowest 3 bits
get_hash()
{
  local id="${1}"

  local h

  case "$((id & 7))" in
  0) h="md5";;
  1) h="sha1";;
  2) h="sha256";;
  3) h="sha384";;
  4) h="sha512";;
  5) h="sha224";;
  *) h="sha224";;
  esac

  echo "${h}"
}

# Get a template name given a number's bits 3,4, and 5
get_template()
{
  local id="${1}"

  local t

  case "$(((id >> 3) & 7))" in
  0) t="ima";;
  1) t="ima-ng";;
  2) t="ima-buf";;
  3) t="ima-sig";;
  4) t="ima-modsig";;
  5) t="evm-sig";;
  *) t="evm-sig";;
  esac

  echo "${t}"
}

hash_algo=$(get_hash "${ID}")
template=$(get_template "${ID}")
mntdir="/mnt"

if ! msg=$(mount -t securityfs "${mntdir}" "${mntdir}" 2>&1); then
  echo " Error: Could not mount securityfs: ${msg}"
  exit "${SKIP:-3}"
fi

if [ ! -f "${mntdir}/ima/hash" ]; then
  echo " Error: Missing hash file in IMA's securityfs"
  exit "${SKIP:-3}"
fi

if [ ! -f "${mntdir}/ima/template_name" ]; then
  echo " Error: Missing template file in IMA's securityfs"
  exit "${SKIP:-3}"
fi

if ! echo "${hash_algo}" > "${mntdir}/ima/hash"; then
  echo " Error: Could not write '${hash_algo}' to IMA securityfs file"
  exit "${FAIL:-1}"
fi

if ! echo "${template}" > "${mntdir}/ima/template_name"; then
  echo " Error: Could not write '${template}' to IMA securityfs file"
  exit "${FAIL:-1}"
fi

if ! echo "1" > "${mntdir}/ima/active"; then
  echo " Error: Could not activate IMA namespace"
  echo " hash:     ${hash_algo}"
  echo " template: ${template}"
  exit "${FAIL:-1}"
fi

t=$(get_template_from_log "${mntdir}")

if [ "${t}" != "${template}" ]; then
  echo " Error: Template in use by namespace is different from the one configured"
  echo " expected : ${template}"
  echo " actual   : ${t}"
fi

h=$(determine_file_hash_from_log "${mntdir}")

# The 'ima' template only accepts md5 and sha1 and falls back to sha1 for all others
# so just check the other ones templates.
if [ "${t}" !=  "ima" ]; then
  if [ "${h}" != "${hash_algo}" ]; then
    echo " Error: Hash algo in use by namespace is different from the one configured"
    echo " expected : ${hash_algo}"
    echo " actual   : ${h}"
  fi
fi

# cat "${mntdir}/ima/ascii_runtime_measurements"

exit "${SUCCESS:-0}"
