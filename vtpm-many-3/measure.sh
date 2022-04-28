#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059

# Caller must pass:
# NSID: distinct namespace id number
# FAILFILE: name of file to create upon failure
NSID=${NSID:-1}

. ./ns-common.sh

SWTPM_LOG="/swtpm-${NSID}/log"

# start vTPM before IMA-ns activation
start_swtpm_chardev "${NSID}" "${VTPM_DEVICE_FD}" --log "level=2,file=${SWTPM_LOG}" --tpm2

mnt_securityfs "/mnt"

pcr=$((NSID % 10)) # pcr=[0..9]
policy="measure func=BPRM_CHECK mask=MAY_EXEC pcr=${pcr} uid=0 "

echo "${policy}" > /mnt/ima/policy || {
  echo " Error: Could not set measure policy. Does IMA-ns support IMA-measurement?"
  exit "${SKIP:-3}"
}

nspolicy=$(cat /mnt/ima/policy)
if [ "${policy}" != "${nspolicy}" ]; then
  echo " Error: Bad policy in namespace."
  echo "expected: ${policy}"
  echo "actual  : ${nspolicy}"
fi

# TPM_CC_PCR_Extend = 0x00000182
# Expect 1 extend for the boot aggregate in PCR 10
ctr_extends=$(grep -c \
                   -E '^ 80 02 00 00 0. .. 00 00 01 82 00 00 00 0A 00 00' \
                   "${SWTPM_LOG}")
ctr_measure=$(grep -c -E "^10 " /mnt/ima/ascii_runtime_measurements)
exp="1"
if [ "${exp}" -ne "${ctr_extends}" ]; then
  echo " Error: Expected ${exp} extends for PCR 10 but found ${ctr_extends}."
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi
if [ "${ctr_measure}" -ne "${ctr_extends}" ]; then
  echo " Error: Expected ${ctr_measure} PCR_Extends but found ${ctr_extends}."
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

# Expect 1 extend for 'busybox' measurement to PCR ${pcr}
pcr_hex=$(printf "%02x" "${pcr}")
ctr_extends=$(grep -c \
                   -E "^ 80 02 00 00 0. .. 00 00 01 82 00 00 00 ${pcr_hex} 00 00" \
                   "${SWTPM_LOG}")
ctr_measure=$(grep -c -E "^ ${pcr} " /mnt/ima/ascii_runtime_measurements)
exp="1"
if [ "${exp}" -ne "${ctr_extends}" ]; then
  echo " Error: Expected ${exp} PCR_Extends for PCR ${pcr} but found ${ctr_extends}."
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi
if [ "${ctr_measure}" -ne "${ctr_extends}" ]; then
  echo " Error: Expected ${ctr_measure} PCR_Extends for PCR ${pcr} but found ${ctr_extends}."
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
