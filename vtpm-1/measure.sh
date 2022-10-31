#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3037

. ./ns-common.sh

# start vTPM before IMA-ns activation
start_swtpm_chardev "0" "${VTPM_DEVICE_FD}" --log level=2,file=/swtpm.log

mnt_securityfs "${SECURITYFS_MNT}"

policy='measure func=BPRM_CHECK mask=MAY_EXEC uid=0'

echo "${policy}" > "${SECURITYFS_MNT}/ima/policy" || {
  echo " Error: Could not set measure policy. Does IMA-ns support IMA-measurement?"
  exit "${SKIP:-3}"
}

cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements" >/dev/null

# TPM_ORD_Extend = 0x00000014
ctr_extends=$(grep -c \
                   -E '^ 00 C1 00 00 00 22 00 00 00 14 00 00 00 0A .. ..' \
                   /swtpm.log)
ctr_measure=$(grep -c ^ "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr_measure}" -ne "${ctr_extends}" ]; then
  msg="$(dmesg --ctime --since '30 seconds ago' | grep "tpm${VTPM_DEVICE_NUM}:")"
  echo -e " Error: Expected ${ctr_measure} PCR_Extend's but found ${ctr_extends}.\n" \
          " dmsg output for last 30 seconds for tpm${VTPM_DEVICE_NUM}: ${msg}"
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
