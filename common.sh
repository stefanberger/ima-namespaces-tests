#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

# Shellcheck: ignore=SC2032

AUDITLOG=/var/log/audit/audit.log

if [ "$(id -u)" -ne 0 ] && [ -n "${HOME}" ]; then
  WORKDIR="${IMA_TEST_WORKDIR:-${HOME}/.imatest}"
else
  WORKDIR="${IMA_TEST_WORKDIR:-/var/lib/imatest}"
fi

if [ -n "${IMA_TEST_UML}" ]; then
  if [ ! -x "${IMA_TEST_UML}" ]; then
    echo " Error: IMA_TEST_UML must point to the Linux UML executable"
    exit "${FAIL:-1}"
  fi
  if [[ ${IMA_TEST_WORKDIR} =~ \. ]]; then
    # When there's a '.' in the pathname for the root dir for UML then
    # the whole parameter to UML disappears
    echo " Error: IMA_TEST_WORKDIR must not contain a '.' in the path!"
    exit "${FAIL:-1}"
  fi
  if [ "$(id -u)" != 0 ]; then
    # The directory we create for mounting the loopback-mounted filesystem
    # must have the same owner on the host as inside UML. This seems to only
    # work for root.
    echo " Error: Must be root to use UML"
    exit "${FAIL:-1}"
  fi
  # on UML we don't need securityfs on the host; we can just hard code the path
  SECURITYFS_MNT=/mnt
  AUDITLOG="${WORKDIR}/audit.log"
else
  SECURITYFS_MNT="$(mount \
		    | sed -n 's/.* on \(.*\) type securityfs .*/\1/p' \
		    | sed -n 1p)"
  if [ -z "${SECURITYFS_MNT}" ]; then
    echo "Error: Could not determine securityfs mount point."
    exit "${FAIL:-1}"
  fi
fi

case "${IMA_TEST_ENV}" in
""|container)
  ;;
*)
  echo " Error: IMA_TEST_ENV must be either unset or have value 'container'"
  exit "${FAIL:-1}"
  ;;
esac

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

# Find a particular string in the audit log a number of times
#
# @param1: The string to find in the audit log; this can be a grep regex
# @param2: The expected number of times to find the string
# @param3: The number of times to retry after waiting for 0.1s
function auditlog_find()
{
  local regex="$1"
  local exp="$2"
  local retries="$3"

  local ctr

  ctr="$(wait_num_entries "${AUDITLOG}" "${regex}" "${exp}" "${retries}")"
  if [ "${ctr}" -ne "${exp}" ]; then
    echo " Error: Could not find '${regex}' ${exp} times in audit log, found it ${ctr} times."
    exit "${FAIL:-1}"
  fi
}

# Check whether the host has IMA support
function check_ima_support()
{
  if [ -n "${IMA_TEST_UML}" ]; then
    return
  fi

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

# Setup a filesystem (for a container) with statically linked busybox inside
# @param1: For container set '1', for host set '0'
# @param2...: Files to copy into the filesystem
function __setup_busybox()
{
  local forcontainer="$1"; shift

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

  if [ "${forcontainer}" -eq 1 ] || [ -n "${IMA_TEST_UML}" ] ; then
    mkdir -p "${rootfs}"/{bin,mnt,proc,dev}
    if [ "$(id -u)" = "0" ]; then
      rm -f "${rootfs}"/dev/kmsg
      mknod "${rootfs}"/dev/kmsg c 1 11
    fi
  else
    mkdir -p "${rootfs}"/bin
  fi

  while [ $# -ne 0 ]; do
    if ! cp -H "$1" "${rootfs}"; then
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
      cat chmod cut cp date dirname diff echo env find grep head id \
      ls ln mkdir mknod mount mv printf rm \
      sed sh sha1sum sha256sum sha384sum sha512sum sleep stat sync \
      tail time uname which; do
    ln -s busybox ${prg}
  done
  popd 1>/dev/null || exit "${FAIL:-1}"

  if ! cp "${busybox}" "${rootfs}/bin/busybox2"; then
    echo "Error: Failed to copy ${busybox} to ${rootfs}/bin/busybox2"
    exit "${FAIL:-1}"
  fi
  echo >> "${rootfs}/bin/busybox2"
}

# Setup a filesystem for a container with statically linked busybox
# @param1...: Files to copy into the filesystem
function setup_busybox_container()
{
  __setup_busybox 1 "$@"
}

# Setup a filesystem with statically linked busybox
# @param1...: Files to copy into the filesystem
function setup_busybox_host()
{
  __setup_busybox 0 "$@"
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

function __post_uml_run()
{
  local rc="$1"
  local rootfs="$2"
  local stdoutlog="$3"
  local verbosity="$4"
  local stderrlog="$5"

  case "${rc}" in
  0)
    if [ -r "${rootfs}/__exitcode" ]; then
      rc="$(cat "${rootfs}/__exitcode")"
    else
      echo "Error: Missing file ${rootfs}/__exitcode"
      rc="${FAIL:-1}"
    fi
    ;;
  127) # binary is missing
    rc="${FAIL:-1}";;
  134) # binary aborted
    rc="${FAIL:-1}"
    echo "=============== stdout ==============="
    cat "${stdoutlog}"
    if [ -r "${stderrlog}" ]; then
      echo "=============== stderr ==============="
      cat "${stderrlog}"
    fi
    echo "======================================"
    ;;
  esac
  # Generate audit log from stdoutlog
  sed -n "/^audit:/p" < "${stdoutlog}" > "${AUDITLOG}"
  # Display linux & test output other than audit messages
  if [ "${verbosity}" -eq 0 ]; then
    # Filter-out a couple of known Linux dmesg lines
    sed -e '1,/\.sh as init process$/ d' \
        -e '/^audit:/d' \
        -e '/^ima:/d' \
        -e '/^integrity:/d' \
        -e '/^loop0:/d' \
        -e '/^EXT4-fs/d' \
        -e '/^Joined session/d' \
        -e '/^reboot:/d' \
        -e '/^[[:space:]]*$/d' \
        < "${stdoutlog}"
  fi

  return "${rc}"
}

function get_verbosity()
{
  if [[ "${IMA_TEST_VERBOSE}" =~ ^[0-9]+$ ]]; then
    echo "${IMA_TEST_VERBOSE}"
  elif [ -n "${IMA_TEST_VERBOSE}" ]; then
    echo 1
  else
    echo 0
  fi
}

# Run the given executable or script on the host with a restricted PATH to only
# make executables available previously copied using setup_busybox_host().
# @param1...: Executable and parameters
#
# Note: Only global/environment variables with the prefixes 'G_' & 'IMA_TEST_'
# will be passed through to bash in UML.
# The global variable UML_KERNEL_CMD may be used to pass Linux kernel command
# line parameter to UML Linux.
function run_busybox_host()
{
  local rootfs rc stdoutlog stderrlog redir verbosity cmd

  rootfs="$(get_busybox_container_root)"

  pushd "${rootfs}" 1>/dev/null || exit "${FAIL:-1}"

  if [ -n "${IMA_TEST_UML}" ]; then
    if [ "${IMA_TEST_ENV}" = "container" ]; then
      cmd="unshare --user --map-root-user --mount-proc --pid --fork --root ${rootfs}/mntpoint"
    else
      cmd="chroot ${rootfs}/mntpoint"
    fi

    stdoutlog="${rootfs}/.stdoutlog"
    stderrlog="${rootfs}/.stderrlog"
    verbosity=$(get_verbosity)
    [ "${verbosity}" -gt 0 ] && redir=/dev/stdout || redir=/dev/null

    # shellcheck disable=SC2145
    ${IMA_TEST_UML} \
      SUCCESS="${SUCCESS:-0}" FAIL="${FAIL:-1}" SKIP="${SKIP:-3}" \
      PATH="/bin:/usr/bin:/usr/sbin:${rootfs}/bin:${rootfs}/usr/bin" SECURITYFS_MNT="/mnt" \
      UML_SCRIPT="$1" UML_SCRIPT_P1="$2" \
      "$(set | grep -E "^(G|IMA_TEST)_.*=.*")" \
      ${UML_KERNEL_CMD:+${UML_KERNEL_CMD}} \
      rootfstype=hostfs rw init="${rootfs}/uml_chroot.sh ${cmd}" mem=256M \
      1> >(tee "${stdoutlog}" 2>/dev/null | sed -z 's/\n/\n\r/g' >${redir}) \
      2> >(tee "${stderrlog}" 2>/dev/null | sed -z 's/\n/\n\r/g' >${redir})
    __post_uml_run "$?" "${rootfs}" "${stdoutlog}" "${verbosity}" "${stderrlog}"
    rc=$?
  else
    SUCCESS=${SUCCESS:-0} FAIL=${FAIL:-1} SKIP=${SKIP:-3} \
    PATH="${rootfs}/bin:${rootfs}/usr/bin" SECURITYFS_MNT="${SECURITYFS_MNT}" \
      "$@"
    rc=$?
  fi

  popd 1>/dev/null || exit "${FAIL:-1}"

  return $rc
}

# Run the given executable or script in the busybox container
# @param1...: Executable and parameters
#
# Note: Only global/environment variables with the prefixes 'G_' & 'IMA_TEST_'
# will be passed through to bash in UML.
function run_busybox_container()
{
  local rootfs rc stdoutlog stderrlog redir verbosity cmd

  rootfs="$(get_busybox_container_root)"

  if [ -n "${IMA_TEST_UML}" ]; then
    if [ "${IMA_TEST_ENV}" = "container" ]; then
      cmd="unshare --user --map-root-user --mount-proc --pid --fork --root ${rootfs}/mntpoint"
    else
      cmd="chroot ${rootfs}/mntpoint"
    fi

    stdoutlog="${rootfs}/.stdoutlog"
    stderrlog="${rootfs}/.stderrlog"
    verbosity=$(get_verbosity)
    [ "${verbosity}" -gt 0 ] && redir=/dev/stdout || redir=/dev/null

    # shellcheck disable=SC2145
    ${IMA_TEST_UML} \
      SUCCESS="${SUCCESS:-0}" FAIL="${FAIL:-1}" SKIP="${SKIP:-3}" \
      PATH="/bin:/usr/bin:/usr/sbin:${rootfs}/bin:${rootfs}/usr/bin" SECURITYFS_MNT="/mnt" \
      UML_SCRIPT="$1" UML_SCRIPT_P1="$2" \
      "$(set | grep -E "^(G|IMA_TEST)_.*=.*")" \
      rootfstype=hostfs rw init="${rootfs}/uml_chroot.sh ${cmd}" mem=256M \
      1> >(tee "${stdoutlog}" 2>/dev/null | sed -z 's/\n/\n\r/g' >${redir}) \
      2> >(tee "${stderrlog}" 2>/dev/null | sed -z 's/\n/\n\r/g' >${redir})
    __post_uml_run "$?" "${rootfs}" "${stdoutlog}" "${verbosity}" "${stderrlog}"
    rc=$?
  else
    SUCCESS=${SUCCESS:-0} FAIL=${FAIL:-1} SKIP=${SKIP:-3} \
    PATH=/bin:/usr/bin SECURITYFS_MNT="/mnt" IN_NAMESPACE="1" \
    unshare --user --map-root-user --mount-proc --pid --fork \
      --root "${rootfs}" "$@"
    rc=$?
  fi

  return $rc
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
  PATH=/bin:/usr/bin SECURITYFS_MNT="/mnt" IN_NAMESPACE="1" \
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
  PATH=/bin:/usr/bin SECURITYFS_MNT="${mnt}" IN_NAMESPACE="1" \
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
#
# Note: Only global/environment variables with the prefixes 'G_' & 'IMA_TEST_'
# will be passed through to bash in UML.
function run_busybox_container_key_session()
{
  local rootfs rc stdoutlog stderrlog redir verbosity cmd

  rootfs="$(get_busybox_container_root)"

  if [ -n "${IMA_TEST_UML}" ]; then
    if [ "${IMA_TEST_ENV}" = "container" ]; then
      cmd="unshare --user --map-root-user --mount-proc --pid --fork --root ${rootfs}/mntpoint keyctl session - "
    else
      cmd="chroot ${rootfs}/mntpoint keyctl session - "
    fi

    stdoutlog="${rootfs}/.stdoutlog"
    stderrlog="${rootfs}/.stderrlog"
    verbosity=$(get_verbosity)
    [ "${verbosity}" -gt 0 ] && redir=/dev/stdout || redir=/dev/null

    # shellcheck disable=SC2145
    ${IMA_TEST_UML} \
      SUCCESS="${SUCCESS:-0}" FAIL="${FAIL:-1}" SKIP="${SKIP:-3}" \
      PATH="/bin:/usr/bin:/usr/sbin:${rootfs}/bin:${rootfs}/usr/bin" SECURITYFS_MNT="/mnt" \
      UML_SCRIPT="$1" UML_SCRIPT_P1="$2" \
      "$(set | grep -E "^(G|IMA_TEST)_.*=.*")" \
      rootfstype=hostfs rw init="${rootfs}/uml_chroot.sh ${cmd}" mem=256M \
      1> >(tee "${stdoutlog}" 2>/dev/null | sed -z 's/\n/\n\r/g' >${redir}) \
      2> >(tee "${stderrlog}" 2>/dev/null | sed -z 's/\n/\n\r/g' >${redir})
    __post_uml_run "$?" "${rootfs}" "${stdoutlog}" "${verbosity}" "${stderrlog}"
    rc=$?
  else
    SUCCESS=${SUCCESS:-0} FAIL=${FAIL:-1} SKIP=${SKIP:-3} \
    PATH=/bin:/usr/bin SECURITYFS_MNT="/mnt" IN_NAMESPACE="1" \
    unshare --user --map-root-user --mount-proc --pid --fork \
      --root "${rootfs}" keyctl session - "$@" \
      2> >(sed '/^Joined session.*/d')
    rc=$?
  fi
  return $rc
}


# Run the given executable or script in the busybox container
# and allow nested creation of user namespaces
function run_busybox_container_nested()
{
  local rootfs

  rootfs="$(get_busybox_container_root)"

  pushd "${rootfs}" 1>/dev/null || exit "${FAIL:-1}"

  SUCCESS=${SUCCESS:-0} FAIL=${FAIL:-1} SKIP=${SKIP:-3} \
  PATH="${rootfs}"/bin:"${rootfs}"/usr/bin SECURITYFS_MNT="/mnt" IN_NAMESPACE="1" \
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
  [ -n "${IMA_TEST_UML}" ] && [ "${IMA_TEST_ENV}" != "container" ] && return 0
  run_busybox_container ./check.sh audit &>/dev/null
}

# Check whether the namespace has IMA-measure support
function check_ns_measure_support()
{
  [ -n "${IMA_TEST_UML}" ] && [ "${IMA_TEST_ENV}" != "container" ] && return 0
  run_busybox_container ./check.sh measure &>/dev/null
}

# Check whether the namespace has IMA-appraise support
function check_ns_appraise_support()
{
  [ -n "${IMA_TEST_UML}" ] && [ "${IMA_TEST_ENV}" != "container" ] && return 0
  run_busybox_container ./check.sh appraise &>/dev/null
}

# Check whether the namespace has IMA-appraise hash support
function check_ns_hash_support()
{
  [ -n "${IMA_TEST_UML}" ] && [ "${IMA_TEST_ENV}" != "container" ] && return 0
  run_busybox_container ./check.sh hash &>/dev/null
}

# Check whether there is SELinux support
function check_ns_selinux_support()
{
  [ -n "${IMA_TEST_UML}" ] && [ "${IMA_TEST_ENV}" != "container" ] && return 0
  run_busybox_container ./check.sh selinux &>/dev/null
}

# Check whether there is vtpm support
function check_ns_vtpm_support()
{
  run_busybox_container_vtpm "1" ./check.sh vtpm
}

# Check whether EVM is supported in namespace (current not at all)
function check_ns_evm_support()
{
  [ -n "${IMA_TEST_UML}" ] && [ "${IMA_TEST_ENV}" != "container" ] && return 0
  run_busybox_container ./check.sh evm &>/dev/null
}

# Check whether the given kernel version string is valid
function is_valid_kernel_version()
{
  local version="$1"

  local micro

  # shellcheck disable=SC2001
  micro=$(sed 's/^\([[:digit:]]\+\)\.\([[:digit:]]\+\)\.\([[:digit:]]\+\).*/\3/p' <<< "${version}")
  [ -n "${micro}" ] && return 0
  return 1
}

# Test kernel version 1 >= kernel version 2
# @param1: Kernel version 1
# @param2: Kernel version 2
function kernel_version_ge()
{
  local v1="$1"
  local v2="$2"

  local t1 t2 regex

  regex='s/^\([[:digit:]]\+\)\.\([[:digit:]]\+\)\.\([[:digit:]]\+\).*/'

  # compare major
  t1=$(sed -n "${regex}\1/p" <<< "${v1}")
  t2=$(sed -n "${regex}\1/p" <<< "${v2}")
  if [ -z "$t1" ] || [ -z "$t2" ]; then
    return 2
  fi
  [ "$t1" -lt "$t2" ] && return 1
  [ "$t1" -gt "$t2" ] && return 0

  # compare minor
  t1=$(sed -n "${regex}\2/p" <<< "${v1}")
  t2=$(sed -n "${regex}\2/p" <<< "${v2}")
  if [ -z "$t1" ] || [ -z "$t2" ]; then
    return 2
  fi
  [ "$t1" -lt "$t2" ] && return 1
  [ "$t1" -gt "$t2" ] && return 0

  # compare micro
  t1=$(sed -n "${regex}\3/p" <<< "${v1}")
  t2=$(sed -n "${regex}\3/p" <<< "${v2}")
  if [ -z "$t1" ] || [ -z "$t2" ]; then
    return 2
  fi
  [ "$t1" -lt "$t2" ] && return 1

  return 0
}

# Get the kernel version of the kernel we will run on, such as the
# UML kernel or the local kernel
# @param1: Kernel version string with in format <major>.<minor>.<micro>...
function get_kernel_version()
{
  local v rc ver temp

  # temporarily turn off vebose mode
  temp=${IMA_TEST_VERBOSE};IMA_TEST_VERBOSE=0

  v=$(run_busybox_host ./check.sh get-kernel-version)
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "Error: Could not determine kernel version"
    exit "${FAIL:-1}"
  fi

  IMA_TEST_VERBOSE=${temp}

  ver=$(sed -n 's/KERNELVERSION: \(.*\)/\1/p' <<< "${v}")
  if ! is_valid_kernel_version "${ver}"; then
    echo "Error: The kernel version ${ver} was not found to be valid."
    exit "${FAIL:-1}"
  fi
  echo "${ver}"
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
