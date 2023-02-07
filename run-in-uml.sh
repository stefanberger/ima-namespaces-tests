#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause
# set -x

# Set up a filesystem with all the tools installed to 'busybox container root'
# and start UML with this filesystem.
# Note: The filesystem that UML will use does NOT let UML set xattrs. We would
#       need to use 'chroot' for this to work but then unshare wouldn't work
#       anymore for the test cases.
#
# @param1: Executable/script to run under UML
function uml_run_script()
{
  local script="$1"

  local rootfs rc err dev f stdoutlog stderrlog verbosity redir

  rootfs="$(get_busybox_container_root)"

  pushd "${rootfs}" 1>/dev/null || exit "${FAIL:-1}"

  if ! err=$(dd if=/dev/zero of=.myimage bs=1M count=100 2>&1); then
    echo "Error: dd failed: ${err}"
    exit "${FAIL:-1}"
  fi

  if ! err=$(losetup -f .myimage --show); then
    echo " Error: losetup failed: ${err}"
    exit "${FAIL:-1}"
  fi
  dev=$err

  if ! err=$(mkfs.ext4 -b 4096 "${dev}" 2>&1); then
    echo "Error: mkfs.ext4 failed: ${err}"
    exit "${FAIL:-1}"
  fi

  if ! err=$(mkdir mntpoint 2>&1); then
    echo "Error: mkdir failed: ${err}"
    exit "${FAIL:-1}"
  fi

  if ! err=$(mount -o i_version "${dev}" mntpoint 2>&1); then
    echo "Error: mount failed: ${err}"
    exit "${FAIL:-1}"
  fi

  for f in *; do
    if [ "${f}" = "mntpoint" ]; then
      continue
    fi
    if [ ! -e "mntpoint/${f}" ]; then
      if ! err=$(cp -r "${f}" mntpoint 2>&1); then
        echo "Error: cp ${f} failed: ${err}"
        exit "${FAIL:-1}"
      fi
    fi
  done

  stdoutlog="${rootfs}/.stdoutlog"
  stderrlog="${rootfs}/.stderrlog"
  verbosity=$(get_verbosity)
  [ "${verbosity}" -gt 0 ] && redir=/dev/stdout || redir=/dev/null

  ${IMA_TEST_UML} \
    SUCCESS="${SUCCESS:-0}" FAIL="${FAIL:-1}" SKIP="${SKIP:-3}" \
    "$(set | grep -E "^(G_|IMA_TEST_EXPENSIVE).*=.*")" \
    UML_SCRIPT="${script}" \
    rootfstype=hostfs rootflags="${rootfs}/mntpoint" rw init="uml_run.sh" mem=256M \
    1> >(tee "${stdoutlog}" 2>/dev/null | sed -z 's/\n/\n\r/g' >${redir}) \
    2> >(tee "${stderrlog}" 2>/dev/null | sed -z 's/\n/\n\r/g' >${redir})
  __post_uml_run "$?" "${rootfs}/mntpoint" "${stdoutlog}" "${verbosity}" "${stderrlog}"
  rc=$?

  umount mntpoint
  losetup -d "${dev}"

  popd &>/dev/null || exit 1

  return "${rc}"
}


function setup_filesystem_for_uml()
{
  local testscript="$1"

  local rootfs prg

  # shellcheck disable=SC2119
  setup_busybox_container

  # Set up a minimal environment that most test cases can work with
  for prg in busybox unshare bash file auditd true; do
    copy_elf_busybox_container "$(type -P "${prg}")" "bin/"
  done

  rootfs="$(get_busybox_container_root)"

  # own nproc that shows a few more CPUs than what nproc would shows in UML (1 CPU)
  cat <<_EOF_ >> "${rootfs}/bin/nproc"
#!/bin/bash
echo 10
_EOF_
  chmod 755 "${rootfs}/bin/nproc"

  cp "$(type -P ldd)" "${rootfs}/bin"

  # file utility needs a few helper files
  mkdir -p "${rootfs}/etc"
  cp "/etc/magic" "${rootfs}/etc"

  mkdir -p "${rootfs}/usr/share/misc"
  cp -rLp /usr/share/misc/ "${rootfs}/usr/share/"

  # Copy common.sh ns-common.sh etc. (*.sh) and test case directory
  cp -rpH ./*.sh "$(dirname "${testscript}")" "${rootfs}"


  # auditd:
  # don't copy host's /etc/audit/ since auditd won't run anymore at all then

  # fake systemctl for checking on auditd
  cat <<_EOF_ >> "${rootfs}/bin/systemctl"
#!/bin/bash
exit 0
_EOF_
  chmod 755 "${rootfs}/bin/systemctl"
}

DIR="$(dirname "$0")"
ROOT="${DIR}"

source "${ROOT}/common.sh"

setup_filesystem_for_uml "$1"

uml_run_script "$@"
exit $?
