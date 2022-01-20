#!/usr/bin/env bash

# Shellcheck: ignore=SC2032

AUDITLOG=/var/log/audit/audit.log

if [ "$(id -u)" -ne 0 ] && [ -n "${HOME}" ]; then
 WORKDIR="${HOME}/.imatest"
else
 WORKDIR="/var/run/imatest"
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
    cp "$1" "${rootfs}"
    shift
  done

  cp "${busybox}" "${rootfs}/bin"
  pushd "${rootfs}/bin" 1>/dev/null || exit "${FAIL:-1}"
  for prg in \
      cat chmod cut cp echo env find grep ls mkdir mount rm \
      sh sha1sum sha256sum sha384sum sha512sum sleep sync tail which; do
    ln -s busybox ${prg}
  done
  popd 1>/dev/null || exit "${FAIL:-1}"

  cp "${busybox}" "${rootfs}/bin/busybox2"
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
  cp "${executable}" "${destfile}"

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
# @param2: Number of times to try with 0.1s waits in betwen
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
