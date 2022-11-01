#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# Shellcheck: ignore=SC2032

AUDITLOG=/var/log/audit/audit.log

if [ "$(id -u)" -ne 0 ] && [ -n "${HOME}" ]; then
  WORKDIR="${IMA_TEST_WORKDIR:-${HOME}/.imatest}"
else
  WORKDIR="${IMA_TEST_WORKDIR:-/var/lib/imatest}"
fi

SECURITYFS_MNT="$(mount  | sed -n 's/^securityfs on \(.*\) type .*/\1/p')"
if [ -z "${SECURITYFS_MNT}" ]; then
  echo "Error: Could not determine securityfs mount point."
  exit "${FAIL:-1}"
fi

# Check whether current user is root
function check_root()
{
  if [ "$(id -u)" -ne 0 ]; then
    echo " Error: Need to be root to run this test."
    exit "${SKIP:-3}"
  fi
}

# Check whether running as root or otherwise if password-less sudo is
# possible if it is allowed
#
# Environment or global variables:
# IMA_TEST_ALLOW_SUDO: non-empty if usage of sudo is to be allowed
function check_root_or_sudo()
{
  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi
  # not root; check sudo usage if allowed
  if [ -n "${IMA_TEST_ALLOW_SUDO}" ]; then
    if ! sudo -v -n &>/dev/null; then
      echo " Error: Password-less sudo does NOT work."
      exit "${SKIP:-3}"
    fi
  else
    echo " Error: Did not test whether password-less sudo works. Need env. var. IMA_TEST_ALLOW_SUDO to be set."
    exit "${SKIP:-3}"
  fi
}

# Check whether the vtpm proxy device is available; try to enable it by
# loading the kernel module
function check_vtpm_proxy_device
{
  if [ ! -c /dev/vtpmx ]; then
    if ! modprobe tpm_vtpm_proxy; then
      echo " Error: Could not run 'modprobe tpm_vtpm_proxy'. VTPM proxy device not available."
      exit "${SKIP:-3}"
    fi
  fi
}

# Check whether auditd is running
function check_auditd()
{
  if ! systemctl status auditd &>/dev/null; then
    echo " Error: Audit daemon seems to not be running."
    exit "${FAIL:-1}"
  fi
  if [ ! -f "${AUDITLOG}" ]; then
    echo " Error: Could not find audit log at expected location: ${AUDITLOG}"
    exit "${FAIL:-1}"
  fi
}

# Get the size (filesize) of the audit log
#
# Environment or global variables:
# AUDITLOG: full path to the audit log
function get_auditlog_size()
{
  stat -c%s "${AUDITLOG}"
}

# Check whether the host has IMA support
function check_ima_support()
{
  if [ ! -f "${SECURITYFS_MNT}/ima/ascii_runtime_measurements" ]; then
    echo " Info: IMA not supported by this kernel ($(uname -rs))"
    exit "${SKIP:-3}"
  fi
}

# Check whether SELinux is enabled on the host
function check_selinux_enabled()
{
  if ! type -p selinuxenabled | grep -q ^; then
    echo " Error: selinuxenabled tool is not installed"
    exit "${SKIP:-3}"
  fi

  if ! selinuxenabled; then
    echo " Error: SELinux is not enabled on this machine"
    exit "${SKIP:-3}"
  fi
}

# Check whether swtpm supports tpm-1.2 or tpm-2.0
# @param1: either 'tpm-1.2' or 'tpm-2.0'
function __check_swtpm_tpmXX_support()
{
  local searchkey="$1"

  local tmp

  if ! type -P swtpm >/dev/null; then
    echo " Error: swtpm seems to not be installed"
    exit "${SKIP:-3}"
  fi

  tmp="$(swtpm socket --print-capabilities)"
  # tpm-1.2 was printed starting when the 'version' field appeared
  if [ -n "$(echo "${tmp}" | sed -n 's/.*"version": "\([0-9\.]*\)".*/\1/p')" ]; then
    if ! echo "${tmp}" | grep -q "\"${searchkey}\""; then
      echo " Error: swtpm does not support TPM 1.2"
      exit "${SKIP:-3}"
    fi
  fi
}

# Check whether swtpm supports tpm-1.2
function check_swtpm_tpm12_support()
{
   __check_swtpm_tpmXX_support "tpm-1.2"
}

# Check whether swtpm supports tpm-2.0
function check_swtpm_tpm2_support()
{
   __check_swtpm_tpmXX_support "tpm-2.0"
}

# Check whether the user allows running time-consuming tests
#
# Environment or global variable
# IMA_TEST_EXPENSIVE: non-empty to indicate that time-consuming tests may run
function check_allow_expensive_test()
{
  if [ -z "${IMA_TEST_EXPENSIVE}" ]; then
    echo " IMA_TEST_EXPENSIVE environment variable must be set for this test"
    exit "${SKIP:-3}"
  fi
}

# Create the work directory for the IMA tests
function create_workdir()
{
  rm -rf "${WORKDIR}"
  if ! mkdir -p "${WORKDIR}"; then
    echo " Error: Could not create ${WORKDIR}."
    exit "${FAIL:-1}"
  fi
}

# Return the path of the busybox container's root
function get_busybox_container_root()
{
  echo "${WORKDIR}/rootfs"
}

# Setup a simple container with statically linked busybox inside
function setup_busybox_container()
{
  local busybox rootfs

  busybox="$(type -P busybox)"

  if [ -z "${busybox}" ]; then
    echo "Error: Could not find busybox."
    exit "${FAIL:-1}"
  fi
  if ! file "${busybox}" | grep -q "statically"; then
    echo "Error: busybox must be statically linked."
    exit "${FAIL:-1}"
  fi

  create_workdir

  rootfs="$(get_busybox_container_root)"

  mkdir -p "${rootfs}"/{bin,mnt,proc,dev}
  if [ "$(id -u)" = "0" ]; then
    rm -f "${rootfs}"/dev/kmsg
    mknod "${rootfs}"/dev/kmsg c 1 11
  fi

  while [ $# -ne 0 ]; do
    if ! cp "$1" "${rootfs}"; then
      echo "Error: Failed to copy ${1} to ${rootfs}"
      exit "${FAIL:-1}"
    fi
    shift
  done

  if ! cp "${busybox}" "${rootfs}/bin"; then
    echo "Error: Failed to copy ${busybox} to ${rootfs}/bin"
    exit "${FAIL:-1}"
  fi
  pushd "${rootfs}/bin" 1>/dev/null || exit "${FAIL:-1}"
  for prg in \
      cat chmod cut cp date dirname echo env find grep head ls mkdir mount mv printf rm \
      sh sha1sum sha256sum sha384sum sha512sum sleep sync \
      tail time which; do
    ln -s busybox ${prg}
  done
  popd 1>/dev/null || exit "${FAIL:-1}"

  if ! cp "${busybox}" "${rootfs}/bin/busybox2"; then
    echo "Error: Failed to copy ${busybox} to ${rootfs}/bin/busybox2"
    exit "${FAIL:-1}"
  fi
  echo >> "${rootfs}/bin/busybox2"
}

# Copy the given executable and all its libraries into the busybox
# container
# @param1: The full path to the executable
# @param2: Optional directory to install the executable in; if omitted it
#          will be installed under the same path the executable was found
#          (/sbin/foobar will be installed to /sbin/foobar in container fs)
function copy_elf_busybox_container()
{
  local executable="$1"
  local destdir="$2"  # optional

  local destfile dep rootfs

  rootfs="$(get_busybox_container_root)"
  if [ -z "${destdir}" ]; then
    destdir="${rootfs}/$(dirname "${executable}")"
    destfile="${rootfs}/${executable}"
  else
    destdir="${rootfs}/${destdir}"
    destfile="${destdir}/$(basename "${executable}")"
  fi

  if [ -f "${destfile}" ]; then
    return
  fi
  if [ ! -f "${executable}" ]; then
    echo "Executable ${executable} not found on host."
    exit "${SKIP:-3}"
  fi

  #echo "Installing $1 to ${destfile}"
  mkdir -p "${destdir}"
  if ! cp "${executable}" "${destfile}"; then
    echo "Error: Failed to copy ${executable} to ${destfile}"
    exit "${FAIL:-1}"
  fi

  for dep in \
    $(ldd "${executable}" |
      grep -v "=>" | grep -v "vdso" |
      sed -n 's/\s*\([^(]*\) (.*/\1/p') \
    $(ldd "${executable}" |
      grep -v vdso |
      sed -n 's/.*=> \([^(]*\) (.*/\1/p'); do
    copy_elf_busybox_container "${dep}"
  done
}

# Run the given executable or script in the busybox container
function run_busybox_container()
{
  local rootfs

  rootfs="$(get_busybox_container_root)"

  SUCCESS=${SUCCESS:-0} FAIL=${FAIL:-1} SKIP=${SKIP:-3} \
  PATH=/bin:/usr/bin SECURITYFS_MNT="/mnt" \
  unshare --user --map-root-user --mount-proc --pid --fork \
    --root "${rootfs}" "$@"
  return $?
}

# Run the given executable or script in the busybox container and
# setup a vTPM
# @param1: 1 for TPM 2 device, otherwise TPM 1.2
# @param2...: Executable to run and its parameters
#
# Environment or global variables:
# VTPM_EXEC: Path to vtpm-exec program; mandatory
function run_busybox_container_vtpm()
{
  local tpm2="$1"; shift 1

  local rootfs opt

  [ "${tpm2}" -eq 1 ] && opt="--create-tpm2-device" || opt="--create-tpm1.2-device"

  rootfs="$(get_busybox_container_root)"

  SUCCESS=${SUCCESS:-0} FAIL=${FAIL:-1} SKIP=${SKIP:-3} \
  PATH=/bin:/usr/bin SECURITYFS_MNT="/mnt" \
  ${VTPM_EXEC} "${opt}" -- \
    unshare --user --map-root-user --mount-proc --pid --fork \
      --root "${rootfs}" "$@"
  return $?
}

# Run the given executable or script in the busybox container
# and set the policy via nsenter.
# The test script inside the container must set securityfs and then
# has to wait for the SYNCFILE to disappear
#
# @param1: Mount point of securityfs inside container
# @param2: The policy to set
# @param3... : Executable and parameters
#
# environment variables:
# SYNCFILE: syncfile to use to synchronize with container
# FAILFILE: optional failfile to write in case an error occurs
function run_busybox_container_set_policy()
{
  local mnt="${1}"
  local policy="${2}"
  shift 2

  local rootfs unsharepid childpid c rc policyfile failfile found

  rootfs="$(get_busybox_container_root)"
  failfile="${rootfs}/${FAILFILE}"

  [ -n "${FAILFILE}" ] && rm -f "${failfile}"

  if [ -z "${SYNCFILE}" ]; then
    echo " Error: Missing SYNCFILE env. variable"
    return "${FAIL:-1}"
  fi
  echo > "${rootfs}/${SYNCFILE}"

  SUCCESS=${SUCCESS:-0} FAIL=${FAIL:-1} SKIP=${SKIP:-3} \
  PATH=/bin:/usr/bin SECURITYFS_MNT="${mnt}" \
  unshare --user --map-root-user --mount-proc --pid --fork \
    --root "${rootfs}" "$@" &
  unsharepid=$!

  if ! wait_for_file "/proc/${unsharepid}/task/${unsharepid}/children" 30; then
    echo " Error: Proc file with children did not appear. Did child process die?"
    [ -n "${FAILFILE}" ] && echo > "${failfile}"
    return "${FAIL:-1}"
  fi
  # kernel memory leak detection (CONFIG_DEBUG_KMEMLEAK) makes unshare+fork very slow
  for ((c = 0; c < 100; c++)); do
    childpid=$(head -n1 "/proc/${unsharepid}/task/${unsharepid}/children" | tr -d " ")
    [ -n "${childpid}" ] && break
    sleep 0.1
  done
  if [ -z "${childpid}" ]; then
    echo " Error: Could not get pid of children of unshared process ${unsharepid}"
    [ -n "${FAILFILE}" ] && echo > "${failfile}"
    return "${FAIL:-1}"
  fi

  activefile="${rootfs}${mnt}/ima/active"
  # wait until the active file is there
  found=0
  for ((c = 0; c < 50; c++)); do
    if nsenter --mount -t "${childpid}" /bin/sh -c "[ ! -f ${activefile} ] && exit 1 || exit 0"; then
      found=1
      break
    fi
    sleep 0.1
  done
  if [ "${found}" != "1" ]; then
    echo " Error: ${activefile} did not show up in namespace in time (~5s). Heavily loaded system?"
    return "${FAIL:-1}"
  fi

  # wait until the active file has '1' in it
  for ((c = 0; c < 30; c++)); do
    active=$(nsenter --mount -t "${childpid}" cat "${activefile}")
    [ "${active}" = "1" ] && break
    sleep 0.1
  done

  if [ "${active}" != "1" ]; then
    echo " Error: IMA namespace has not been set active"
    [ -n "${FAILFILE}" ] && echo > "${failfile}"
    return "${FAIL:-1}"
  fi

  policyfile="${rootfs}${mnt}/ima/policy"
  nsenter --mount -t "${childpid}" /bin/sh -c "busybox printf '${policy}' > ${policyfile}"
  rc=$?
  if [ "${rc}" -ne 0 ]; then
    echo " Error: Could not set policy in container using nsenter"
    [ -n "${FAILFILE}" ] && echo > "${failfile}"
    return "${FAIL:-1}"
  fi

  # echo -n "policy in namespace: "; nsenter --mount -t "${childpid}" cat "${policyfile}"

  rm -f "${rootfs}/${SYNCFILE}"

  wait "${unsharepid}"

  return $?
}

# Run the given executable or script in the busybox container and create a key
# session. Filter out output from 'keyctl session' starting with 'Joined session'.
# @param1...: Executable and parameters
function run_busybox_container_key_session()
{
  local rootfs

  rootfs="$(get_busybox_container_root)"

  SUCCESS=${SUCCESS:-0} FAIL=${FAIL:-1} SKIP=${SKIP:-3} \
  PATH=/bin:/usr/bin SECURITYFS_MNT="/mnt" \
  unshare --user --map-root-user --mount-proc --pid --fork \
    --root "${rootfs}" keyctl session - "$@" \
    2> >(sed '/^Joined session.*/d')
  return $?
}


# Run the given executable or script in the busybox container
# and allow nested creation of user namespaces
function run_busybox_container_nested()
{
  local rootfs

  rootfs="$(get_busybox_container_root)"

  pushd "${rootfs}" 1>/dev/null || exit "${FAIL:-1}"

  SUCCESS=${SUCCESS:-0} FAIL=${FAIL:-1} SKIP=${SKIP:-3} \
  PATH="${rootfs}"/bin:"${rootfs}"/usr/bin SECURITYFS_MNT="/mnt" \
  unshare --user --map-root-user --mount-proc --pid --fork \
    --mount "$@"
  rc=$?
  popd 1>/dev/null || exit "${FAIL:-1}"
  return "$rc"
}

# Wait for the given number of entries in the file that may not
# get results immediately, such as the audit log. Once the expected
# number of entries has been seen found wait for 1s and report the
# number of entries found then (in case file hadn't settled, yet)
#
# @param1: The file to grep through
# @param2: The entry to look for; may be a grep regular expression
# @param3: The number of entries to find
# @param4: The number of times to retry after waiting for 0.1s
function wait_num_entries()
{
  local file="$1"
  local entry="$2"
  local numentries="$3"
  local retries="$4"

  local c ctr

  for ((c = 0;  c < retries; c++)); do
    ctr=$(grep -c -E "${entry}" "${file}")
    if [ "${ctr}" -eq "${numentries}" ]; then
      sleep 1
      grep -c -E "${entry}" "${file}"
      return 0
    fi
    sleep 0.1
  done
  echo "${ctr}"
  return 1
}

# Wait for a file to appear
# @param1: Name of the file
# @param2: Number of times to try with 0.1s waits in between
function wait_for_file()
{
  local file="$1"
  local retries="$2"

  local c

  for ((c = 0; c < retries; c++)); do
    if [ -f "${file}" ]; then
       return 0
    fi
    sleep 0.1
  done
  return 1
}

# Wait for the child to exit and exit with its error code unless
# it reports success.
# @param1: child process Id
function wait_child_exit_with_child_failure()
{
  local childpid="$1"

  local rc

  wait "${childpid}"
  rc=$?
  if [ "${rc}" -ne 0 ]; then
    echo " Error: Child returned exit code ${rc}"
    exit "${rc}"
  fi
}

# Get maximum number of keys
function get_max_number_keys()
{
  if [ "$(id -u)" -eq 0 ]; then
    cat /proc/sys/kernel/keys/root_maxkeys
  else
    cat /proc/sys/kernel/keys/maxkeys
  fi
}

# Check whether the namespace has IMA-audit support
function check_ns_audit_support()
{
  run_busybox_container ./check.sh audit
}

# Check whether the namespace has IMA-measure support
function check_ns_measure_support()
{
  run_busybox_container ./check.sh measure
}

# Check whether the namespace has IMA-appraise support
function check_ns_appraise_support()
{
  run_busybox_container ./check.sh appraise
}

# Check whether the namespace has IMA-appraise hash support
function check_ns_hash_support()
{
  run_busybox_container ./check.sh hash
}

# Check whether there is SELinux support
function check_ns_selinux_support()
{
  run_busybox_container ./check.sh selinux
}

# Check whether there is vtpm support
function check_ns_vtpm_support()
{
  run_busybox_container_vtpm "1" ./check.sh vtpm
}

# Check whether EVM is supported in namespace (current not at all)
function check_ns_evm_support()
{
  run_busybox_container ./check.sh evm
}

# Ensure that the host does not have a rule like the given one
# @param1: 'grep -E' type of pattern describing rule to grep for
function check_host_ima_has_no_rule_like()
{
  local pattern="${1}"

  local imapolicy="${SECURITYFS_MNT}/ima/policy"

  check_root_or_sudo

  if [ "$(sudo grep -c -E "${pattern}" "${imapolicy}")" -ne 0 ]; then
    echo "Error: Host policy has a rule matching '${pattern}'"
    exit "${SKIP:-3}"
  fi

  return 0
}
