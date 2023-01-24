#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC3010

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

mount -t proc /proc /proc

# Get G_IMA_TEMPLATE_FMT from command line since it's not passed in usable format
G_IMA_TEMPLATE_FMT=$(sed -n 's/.* ima_template_fmt=\([^ ]\+\) .*/\1/p' < /proc/cmdline)

case "${G_IMA_TEMPLATE_FMT}" in
d-ngv2)
  grephash="ima:${G_IMA_HASH}"
  ;;
*)
  grephash="${G_IMA_HASH}"
  ;;
esac

case "${G_IMA_TEMPLATE_FMT}" in
d)
  # grep for boot_aggregate line
  grepfmt="d [0]+"
  exp=1
  ;;
d-ng)
  # grep for boot_aggregate line
  grepfmt="d-ng ${grephash}:[0]+"
  exp=1
  ;;
d-ng\|d-ng)
  # grep for boot_aggregate line
  grepfmt="d-ng\|d-ng ${grephash}:[0]+ ${grephash}:[0]+"
  exp=1
  ;;
d-ngv2)
  # grep for boot_aggregate line
  grepfmt="d-ngv2 ${grephash}:[0]+"
  exp=1
  ;;
n)
  grepfmt="n .*\/ns-common.sh"
  exp=2
  ;;
n-ng)
  grepfmt="n-ng .*\/ns-common.sh"
  exp=2
  ;;
buf)
  grepfmt="buf\s+"
  exp=1
  ;;
iuid)
  grepfmt="iuid 0"
  exp=1
  ;;
igid)
  grepfmt="igid 0"
  exp=1
  ;;
imode\|n)
  grepfmt="imode\|n [[:digit:]]{5} .*/ns-common.sh"
  exp=2
  ;;
iuid\|igid)
  grepfmt="iuid\|igid 0 0"
  exp=1
  ;;
iuid\|igid\|imode\|d-ng\|buf\|n-ng)
  grepfmt="iuid\|igid\|imode\|d-ng\|buf\|n-ng 0 0 [[:digit:]]{5} ${grephash}:[[:xdigit:]]+  .*\/ns-common.sh"
  exp=2
  ;;
*)
  echo " Error: Unhandled template format '${G_IMA_TEMPLATE_FMT}'"
  exit_test "${FAIL:-1}"
esac

# cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"

if [[ "${G_IMA_POLICY}" =~ tcb ]]; then
  measurementlog_find "${SECURITYFS_MNT}" "^10 [[:xdigit:]]+ ${grepfmt}$" ${exp}
fi

if [[ "${G_IMA_POLICY}" =~ critical_data ]]; then
  measurementlog_find "${SECURITYFS_MNT}" "^10 .* ima-buf .* kernel_version " 1
fi

exit_test "${SUCCESS:-0}"
