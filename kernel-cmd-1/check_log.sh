#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC3010

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

#cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"

case "${G_IMA_TEMPLATE}" in
ima-ngv2|ima-sigv2)
  grephash="ima:${G_IMA_HASH}"
  ;;
*)
  grephash="${G_IMA_HASH}"
  ;;
esac

if [[ "${G_IMA_POLICY}" =~ tcb ]]; then
  measurementlog_find "${SECURITYFS_MNT}" "^10 .* ${G_IMA_TEMPLATE} ${grephash}:.* .*\/ns-common.sh\s*\$" 2
fi

if [[ "${G_IMA_POLICY}" =~ critical_data ]]; then
  measurementlog_find "${SECURITYFS_MNT}" "^10 .* ima-buf .* kernel_version " 1
fi

exit_test "${SUCCESS:-0}"
