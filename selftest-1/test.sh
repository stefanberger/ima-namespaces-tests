#!/usr/bin/env bash

# SPDX-License-Identifier: BSD-2-Clause

DIR="$(dirname "$0")"
ROOT="${DIR}/.."
VTPM_EXEC="${ROOT}/vtpm-exec/vtpm-exec"

source "${ROOT}/common.sh"

setup_busybox_container \
	"${ROOT}/ns-common.sh" \
	"${ROOT}/uml_chroot.sh" \
	"${ROOT}/check.sh" \
	"${DIR}/selftest.sh" \
	"${DIR}/selftest-env.sh"

copy_elf_busybox_container "$(type -P keyctl)"

function check_errcode()
{
  local rc="$1"
  local exp="$2"
  local func="$3"

  if [ "${rc}" -ne "${exp}" ]; then
    echo "Error: '${func}' returned unexpected error code"
    echo "expected: ${exp}"
    echo "actual  : ${rc}"
    exit "${FAIL:-1}"
  fi
}

echo "INFO: Testing return/exit codes from various functions"

# check.sh must return error code 90 for 'selftest'
run_busybox_container ./check.sh selftest
check_errcode "$?" 90 "'check.sh selftest'"

for func in \
    run_busybox_container \
    run_busybox_container_key_session \
    run_busybox_host ;
do
  ${func} ./selftest.sh
  check_errcode "$?" 91 "${func} ./selftest.sh"
  echo " ${func}: success"
done

if [ "$(id -u)" -eq 0 ] && [ -e "${VTPM_EXEC}" ] && [ -z "${IMA_TEST_UML}" ]; then
  if [ ! -c /dev/vtpmx ]; then
    modprobe tpm_vtpm_proxy &>/dev/null
  fi
  if [ -c /dev/vtpmx ]; then
    copy_elf_busybox_container "${VTPM_EXEC}" "bin/"
    func="run_busybox_container_vtpm"
    ${func} 1 ./selftest.sh
    check_errcode "$?" 91 "${func} ./selftest.sh"
    echo " ${func}: success"
  fi
fi

echo "INFO: Return/exit codes test passed"
echo
echo "INFO: Testing availability of environment vars inside test script"

# Expecting return code 90 + $G_FOO = 95
for func in \
    run_busybox_container \
    run_busybox_container_key_session \
    run_busybox_host ;
do
  G_FOO=5 ${func} ./selftest-env.sh
  check_errcode "$?" 95 "${func} ./selftest-env.sh"
  echo " ${func}: success"
done

if [ "$(id -u)" -eq 0 ] && [ -e "${VTPM_EXEC}" ] && [ -z "${IMA_TEST_UML}" ]; then
  copy_elf_busybox_container "${VTPM_EXEC}" "bin/"
  func="run_busybox_container_vtpm"
  G_FOO=5 ${func} 1 ./selftest-env.sh
  check_errcode "$?" 95 "${func} ./selftest-env.sh"
  echo " ${func}: success"
fi

echo "INFO: Environment variables test passed"
echo
echo "INFO: Calling function get_kernel_version and comparing against other kernel version"

kv1=$(get_kernel_version)

for kv2 in "1.2.3-10" "1.2.3";
do
  if ! kernel_version_ge "${kv1}" "${kv2}"; then
    echo "ERROR: ${kv1} >= ${kv2} test did not pass"
    exit "${FAIL:-1}"
  fi
done

echo "kernel version: ${kv1}"

echo "INFO: Test passed"

exit "${SUCCESS:-0}"
