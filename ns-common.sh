#!/bin/env sh

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

  grep boot_aggregate < "${mntdir}/ima/ascii_runtime_measurements" | \
    busybox cut -d" " -f3
}