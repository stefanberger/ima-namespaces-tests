#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3037

. ./ns-common.sh

# start vTPM before IMA-ns activation
start_swtpm_chardev "0" "${VTPM_DEVICE_FD}" --log level=2,file=/swtpm.log --tpm2

mnt_securityfs "/mnt"

policy='measure func=BPRM_CHECK mask=MAY_EXEC uid=0'

echo "${policy}" > /mnt/ima/policy || {
  echo " Error: Could not set measure policy. Does IMA-ns support IMA-measurement?"
  exit "${SKIP:-3}"
}

cat /mnt/ima/ascii_runtime_measurements >/dev/null

# TPM_CC_PCR_Extend = 0x00000182
ctr_extends=$(grep -c \
                   -E '^ 80 02 00 00 0. .. 00 00 01 82 00 00 00 0A 00 00' \
                   /swtpm.log)
ctr_measure=$(grep -c ^ /mnt/ima/ascii_runtime_measurements)
if [ "${ctr_measure}" -ne "${ctr_extends}" ]; then
  msg="$(dmesg --ctime --since '30 seconds ago' | grep "tpm${VTPM_DEVICE_NUM}:")"
  echo -e " Error: Expected ${ctr_measure} PCR_Extend's but found ${ctr_extends}.\n" \
          " dmsg output for last 30 seconds for tpm${VTPM_DEVICE_NUM}: ${msg}"
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
