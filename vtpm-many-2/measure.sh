#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3037

# Caller must pass:
# NSID: distinct namespace id number
# FAILFILE: name of file to create upon failure
NSID=${NSID:-1}
FAILFILE=${FAILFILE:-failfile}

. ./ns-common.sh

SWTPM_LOG="/swtpm-${NSID}/log"

# start vTPM before IMA-ns activation
start_swtpm_chardev "${NSID}" "${VTPM_DEVICE_FD}" --log "level=2,file=${SWTPM_LOG}" --tpm2

mnt_securityfs "${SECURITYFS_MNT}"

policy='measure func=BPRM_CHECK mask=MAY_EXEC uid=0 '

set_measurement_policy_from_string "${SECURITYFS_MNT}" "${policy}" "${FAILFILE}"

cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements" >/dev/null

# TPM_CC_PCR_Extend = 0x00000182
ctr_extends=$(grep -c \
                   -E '^ 80 02 00 00 0. .. 00 00 01 82 00 00 00 0A 00 00' \
                   "${SWTPM_LOG}")
ctr_measure=$(grep -c ^ "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr_measure}" -ne "${ctr_extends}" ]; then
  msg="$(dmesg --ctime --since '30 seconds ago' | grep "tpm${VTPM_DEVICE_NUM}:")"
  echo -e " Error: Expected ${ctr_measure} PCR_Extend's but found ${ctr_extends}.\n" \
          " dmsg output for last 30 seconds for tpm${VTPM_DEVICE_NUM}: ${msg}"
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
