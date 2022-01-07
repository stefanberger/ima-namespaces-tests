#!/usr/bin/env bash

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
  for prg in mount echo ls cat env grep sh sleep which; do
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
  local executable="$1"

  local rootfs

  rootfs="$(get_busybox_container_root)"

  SUCCESS=${SUCCESS:-0} FAIL=${FAIL:-1} SKIP=${SKIP:-3} \
  PATH=/bin:/usr/bin \
  unshare --user --map-root-user --mount-proc --pid --fork \
    --root "${rootfs}" "${executable}"
  return $?
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
