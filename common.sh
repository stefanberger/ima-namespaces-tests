#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# Shellcheck: ignore=SC2032

AUDITLOG=/var/log/audit/audit.log

if [ "$(id -u)" -ne 0 ] && [ -n "${HOME}" ]; then
 WORKDIR="${HOME}/.imatest"
else
 WORKDIR="/var/lib/imatest"
fi

function check_root()
{
  if [ "$(id -u)" -ne 0 ]; then
    echo " Error: Need to be root to run this test."
    exit "${SKIP:-3}"
  fi
}

# Check whether running as root or otherwise if password-less sudo is
# possible if it is allowed
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

function check_ima_support()
{
  if [ ! -f /sys/kernel/security/ima/ascii_runtime_measurements ]; then
    echo " Info: IMA not supported by this kernel ($(uname -rs))"
    exit "${SKIP:-3}"
  fi
}

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

function check_allow_expensive_test()
{
  if [ -z "${IMA_TEST_EXPENSIVE}" ]; then
    echo " IMA_TEST_EXPENSIVE environment variable must be set for this test"
    exit "${SKIP:-3}"
  fi
}

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

# Setup a simple container with statically linke busybox inside
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
      cat chmod cut cp dirname echo env find grep head ls mkdir mount mv printf rm \
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
function copy_elf_busybox_container()
{
  local executable="$1"

  local destdir destfile dep rootfs

  rootfs="$(get_busybox_container_root)"
  destdir="${rootfs}/$(dirname "${executable}")"
  destfile="${rootfs}/${executable}"

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
  PATH=/bin:/usr/bin \
  unshare --user --map-root-user --mount-proc --pid --fork \
    --root "${rootfs}" "$@"
  return $?
}

# Run the given executable or script in the busybox container
# and set the policy via nsenter.
# The test script inside the container must set securityfs and then
# has to wait for teh SYNCFILE to disappear
#
# @param1: Mount point of securityfs inside container
# @param2: The policy to set
# @param3... : Executable and parameters
#
# environment variables:
# SYNCFILE: syncfile to use to synchronize with container
# FAILFILE: optional failfile to write in case an error occurrs
function run_busybox_container_set_policy()
{
  local mnt="${1}"
  local policy="${2}"
  shift 2

  local rootfs unsharepid childpid c rc policyfile failfile

  rootfs="$(get_busybox_container_root)"
  failfile="${rootfs}/${FAILFILE}"

  [ -n "${FAILFILE}" ] && rm -f "${failfile}"

  if [ -z "${SYNCFILE}" ]; then
    echo " Error: Missing SYNCFILE env. variable"
    return "${FAIL:-1}"
  fi
  echo > "${rootfs}/${SYNCFILE}"

  SUCCESS=${SUCCESS:-0} FAIL=${FAIL:-1} SKIP=${SKIP:-3} \
  PATH=/bin:/usr/bin \
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
  for ((c = 0; c < 30; c++)); do
    if nsenter --mount -t "${childpid}" /bin/sh -c "[ ! -f ${activefile} ] && exit 1 || exit 0"; then
      break
    fi
    sleep 0.1
  done
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
function run_busybox_container_key_session()
{
  local executable="$1"

  local rootfs

  rootfs="$(get_busybox_container_root)"

  SUCCESS=${SUCCESS:-0} FAIL=${FAIL:-1} SKIP=${SKIP:-3} \
  PATH=/bin:/usr/bin \
  unshare --user --map-root-user --mount-proc --pid --fork \
    --root "${rootfs}" keyctl session - "${executable}" \
    2> >(sed '/^Joined session.*/d')
  return $?
}


# Run the given executable or script in the busybox container
# and allow nested creation of user namespaces
function run_busybox_container_nested()
{
  local executable="$1"

  local rootfs

  rootfs="$(get_busybox_container_root)"

  pushd "${rootfs}" 1>/dev/null || exit "${FAIL:-1}"

  SUCCESS=${SUCCESS:-0} FAIL=${FAIL:-1} SKIP=${SKIP:-3} \
  PATH="${rootfs}"/bin:"${rootfs}"/usr/bin \
  unshare --user --map-root-user --mount-proc --pid --fork \
    --mount "${executable}"
  rc=$?
  popd 1>/dev/null || exit "${FAIL:-1}"
  return "$rc"
}

# Wait for the given number of entries in the file that may not
# get results immediately, such as the audit log.
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
       echo "${ctr}"
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
