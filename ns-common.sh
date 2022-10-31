#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3043,SC2034,SC3037

EVM_INIT_HMAC=1
EVM_INIT_X509=2
EVM_ALLOW_METADATA_WRITES=4
EVM_SETUP_COMPLETE=$((0x80000000))

# Common functions for the test scripts running in the namespace

# Mount the securityfs with IMA support; if it doesn't work or 
# the ima directory doesn't show up exit with ${SKIP:-3}
# @param1: mount directory
# @param2: hash for IMA to use for measuring apps; ignored if empty string;
#          optional parameter
# @param3: template name for IMA to user for logging; ignored if empty string;
#          optional parameter
#
# Environment variables:
# VTPM_DEVICE_FD: Set by vtpm-exec upon creation of device and contains the
#                 server side file descriptor to use to connect TPM device
#                 to IMA namespace
mnt_securityfs()
{
  local mntdir="$1"
  local imahash="$2"
  local imatemplate="$3"

  local msg dmsgmsg timeout

  if ! msg=$(mount -t securityfs "${mntdir}" "${mntdir}" 2>&1); then
    echo " Error: Could not mount securityfs: ${msg}"
    exit "${SKIP:-3}"
  fi

  if [ ! -d "${mntdir}/ima" ]; then
    echo " Error: SecurityFS does not have the ima directory"
    exit "${SKIP:-3}"
  fi

  if [ -n "${imahash}" ]; then
    if [ ! -f "${mntdir}/ima/hash" ]; then
      echo " Error: IMA's SecurityFS does not have the hash config file"
      exit "${SKIP:-3}"
    fi
    echo "${imahash}" > "${mntdir}/ima/hash"
  fi

  if [ -n "${imatemplate}" ]; then
    if [ ! -f "${mntdir}/ima/template_name" ]; then
      echo " Error: IMA's SecurityFS does not have the template_name config file"
      exit "${SKIP:-3}"
    fi
    echo "${imatemplate}" > "${mntdir}/ima/template_name"
  fi

  if [ -n "${VTPM_DEVICE_FD}" ]; then
      if ! msg=$(vtpm-exec --connect-to-ima-ns "${VTPM_DEVICE_FD}" 2>&1); then
          timeout=10
          dmsgmsg=$(dmesg --ctime --since "${timeout} seconds ago" |
                    grep " tpm${VTPM_DEVICE_NUM}:")
          if [ -n "${dmsgmsg}" ]; then
              # Odd: kernel message may have a later timestamp than the $(date)
              # This has to come out as one message so it's not interleaved with others...
              echo -e " $(date): vtpm-exec on /dev/tpm${VTPM_DEVICE_NUM}: ${msg}\n" \
                      " dmsg output for last ${timeout} seconds for /dev/tpm${VTPM_DEVICE_NUM} : ${dmsgmsg}\n" \
                      " [Timeouts under heavy load may be expected.]"
          else
              echo -e " $(date): vtpm-exec on /dev/tpm${VTPM_DEVICE_NUM}: ${msg}" \
                      " ==> It's not clear what caused the TPM failure on /dev/tpm${VTPM_DEVICE_NUM}"
          fi
          exit "${FAIL:-1}"
      fi
  fi

  echo 1 > "${mntdir}/ima/active"

  if [ -f "${mntdir}/integrity/evm/active" ]; then
    echo 1 > "${mntdir}/integrity/evm/active"
  fi

  return 0
}

# Get the name of the template from the measurement log at the given
# mountpoint
# @param1: securityfs mount point
get_template_from_log()
{
  local mntdir="$1"

  # use busybox to reduce dependency on signed or copied apps
  busybox grep boot_aggregate < "${mntdir}/ima/ascii_runtime_measurements" | \
    busybox cut -d" " -f3
}

# Set the IMA policy from the given string representing the policy
#
# @param1: securityfs mount point
# @param2: The IMA policy as string
# @param3: Optional filename of a file to write to in case of error
# @param4: Type of policy, e.g. 'audit' or 'measurement'; used in error message
# @param5: Whether to read back the policy; 0 for not reading back
set_policy_from_string()
{
  local mntdir="$1"
  local policy="$2"
  local failfile="$3"
  local policytype="$4"
  local readback="$5"

  local nspolicy

  nspolicy=$(cat "${mntdir}/ima/policy")
  if [ "${nspolicy}" != "$(printf "${policy}")" ]; then
    if ! busybox printf "${policy}" > "${mntdir}/ima/policy"; then
      echo " Error: Could not set ${policytype} policy. Does IMA-ns support IMA-${policytype}?"
      exit "${SKIP:-3}"
    fi
    if [ "${readback}" -ne 0 ]; then
      nspolicy=$(cat "${mntdir}/ima/policy" 2>/dev/null)
      if [ "${nspolicy}" != "$(printf "${policy}")" ]; then
        echo " Error: Could not replace existing policy with new policy."
        echo " expected: '$(printf "${policy}")'"
        echo " actual  : '${nspolicy}'"
        if [ -n "${failfile}" ]; then
          echo > "${failfile}"
        fi
        exit "${FAIL:-1}"
      fi
    fi
  fi
}

# Set a measurement policy
#
# @param1: securityfs mount point
# @param2: The IMA policy as string
# @param3: Optional filename of a file to write to in case of error
set_measurement_policy_from_string()
{
  set_policy_from_string "$1" "$2" "$3" "measurement" 1
}

# Set an appraisal policy
#
# @param1: securityfs mount point
# @param2: The IMA policy as string
# @param3: Optional filename of a file to write to in case of error
# @param4: Whether to read back the policy; 0 for not reading back
#          Reading back will only work if the used cli tools are signed
set_appraisal_policy_from_string()
{
  set_policy_from_string "$1" "$2" "$3" "appraisal" "$4"
}

# Let container run into the cage and have it wait - woof!
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

# Let the containers of out the cage - woof! woof!
# @param1: syncfile
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

  case "${template}" in
  ima)
    imahash=$(echo "${line}" | cut -d" " -f4)
    case "${#imahash}" in
    32) imahash="md5";;
    40) imahash="sha1";;
    esac
    ;;
  ima-ns)
    imahash=$(echo "${line}" | cut -d" " -f5 | cut -d":" -f1)
    ;;
  *)
    imahash=$(echo "${line}" | cut -d" " -f4 | cut -d":" -f1)
    ;;
  esac

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

# Get the length of a given hash in bytes
# @param1: Name of the hash
get_hash_length()
{
  local hashname="$1"

  case "${hashname}" in
  md5) echo 16;;
  sha1) echo 20;;
  sha256) echo 32;;
  sha512) echo 64;;
  sha384|sha224|*) echo "unsupported hash: ${hashname}";
  esac
}

# Wait for a file to disappear
# @param1: Name of the file
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

# Start swtpm with the chardev interface inside a container (for testing)
# @param1: Id of the namespace (typically pass NSID when running concurrent
#          containers)
# @param2: file descriptor of the 'server side' file of vtpm_proxy device
start_swtpm_chardev()
{
  local nsid="$1"
  local fd="$2"

  shift 2

  mkdir -p "/swtpm-${nsid}"

  swtpm chardev \
    --tpmstate "dir=/swtpm-${nsid}" \
    --ctrl "type=unixio,path=/swtpm-${nsid}/ctrl" \
    --fd "${fd}" \
    --locality allow-set-locality \
    --flags not-need-init,startup-clear \
    "$@" &
}

# Gracefully stop swtpm
# @param1: Id of the namespace (typically pass NSID when running concurrent
#          containers)
stop_swtpm()
{
  swtpm_ioctl -s --unix "/swtpm-${nsid}/ctrl"
}
