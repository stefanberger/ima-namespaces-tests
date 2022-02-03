#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3043

# Common functions for the test scripts running in the namespace

# Mount the securityfs with IMA support; if it doesn't work or 
# the ima directory doesn't show up exit with ${SKIP:-3}
# @param1: mount directory
mnt_securityfs()
{
  local mntdir="$1"

  local msg

  if ! msg=$(mount -t securityfs "${mntdir}" "${mntdir}" 2>&1); then
    echo " Error: Could not mount securityfs: ${msg}"
    exit "${SKIP:-3}"
  fi

  if [ ! -d "${mntdir}/ima" ]; then
    echo " Error: SecurityFS does not have the ima directory"
    exit "${SKIP:-3}"
  fi

  echo 1 > "${mntdir}/ima/active"

  return 0
}

# Get the name of the template from the measurement log at the given
# mountpoint
get_template_from_log()
{
  local mntdir="$1"

  # use busybox to reduce dependeny on signed or copied apps
  busybox grep boot_aggregate < "${mntdir}/ima/ascii_runtime_measurements" | \
    busybox cut -d" " -f3
}

# Let container run into the cage and have it wait
# @param1: id of container
# @parma2: syncfile
wait_in_cage()
{
  local id="$1"
  local syncfile="$2"

  echo "${id}" >> "${syncfile}"

  while [ -f "${syncfile}" ]; do
    sleep 0.1
  done
}

# Wait until all containers are in the cage
# @param1: id of coordinator container
# @param2: syncfile
# @param3: number of containers to expect in cage including self
wait_cage_full()
{
  local id="$1"
  local syncfile="$2"
  local numcontainers="$3"

  local num

  # add self to cage
  echo "${id}" >> "${syncfile}"

  while :; do
    num=$(grep -c ^ "${syncfile}")
    [ "${num}" -eq "${numcontainers}" ] && break
    sleep 0.1
  done
}

# Let the containers of out the cage
open_cage()
{
  local syncfile="$1"

  rm -f "${syncfile}"
}

# Determine the hash being used by ima for hashing a file
# @param1: securityfs mount point
determine_file_hash_from_log()
{
  local mntdir="$1"

  local imahash line template

  line=$(head -n1 < "${mntdir}/ima/ascii_runtime_measurements")
  template=$(echo "${line}" | cut -d" " -f3)

  if [ "${template}" = "ima" ]; then
    imahash=$(echo "${line}" | cut -d" " -f4)
    case "${#imahash}" in
    32) imahash="md5";;
    40) imahash="sha1";;
    esac
  else
    imahash=$(echo "${line}" | cut -d" " -f4 | cut -d":" -f1)
  fi

  case "${imahash}" in
  md5) ;;
  sha1) ;;
  sha224) ;;
  sha256) ;;
  sha384) ;;
  sha512) ;;
  *) imahash="unsupported hash";;
  esac

  echo "${imahash}"
}

# Hash a file with the given hash
# @param1: hash to use, e.g., sha256 or sha1
# @param2: filename
hash_file()
{
  local hashtouse="$1"
  local filename="$2"

  local tool

  case "${hashtouse}" in
  md5) tool=md5sum;;
  sha1) tool=sha1sum;;
  sha256) tool=sha256sum;;
  sha512) tool=sha512sum;;
  sha384|sha224|*) echo "unsupported hash: ${hashtouse}"; return;;
  esac
  "${tool}" "${filename}" 2>/dev/null | cut -d" " -f1
}

# Wait for a file to disappear
# @param1: Name of the fil
# @param2: Number of times to try with 0.1s wait in between
wait_file_gone()
{
  local file="$1"
  local retries="$2"

  local c

  c=0
  while [ "${c}" -lt "${retries}" ]; do
    if [ ! -f "${file}" ]; then
       return 0
    fi
    c=$((c+1))
    sleep 0.1
  done

  return 1
}
