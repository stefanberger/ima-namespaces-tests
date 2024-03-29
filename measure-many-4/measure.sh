#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3028

# Caller must pass:
# NSID: distinct namespace id number
# FAILFILE: name of file to create upon failure
# NUM_CONTAINERS: number of containers running
NSID=${NSID:-0}
FAILFILE=${FAILFILE:-failfile}

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

policy='measure func=BPRM_CHECK mask=MAY_EXEC uid=0 '

set_measurement_policy_from_string "${SECURITYFS_MNT}" "${policy}" ""

testfile="testfile"

imahash="$(determine_file_hash_from_log "${SECURITYFS_MNT}")"

reported=0

i=1
while [ "${i}" -lt 20 ]; do
  syncfile="syncfile-${i}"

  if [ "${NSID}" -eq "0" ]; then
    # wait for all containers to be in the cage
    wait_cage_full "${NSID}" "${syncfile}" "${NUM_CONTAINERS}"

    if [ "${i}" -gt 10 ]; then
      rm -f "${testfile}"
    fi

    # Create or modify the test file
    if [ ! -f "${testfile}" ]; then
      printf "#!/bin/env sh\necho ${RANDOM}" > "${testfile}"
      chmod 755 "${testfile}"
    else
      printf "${RANDOM}" >> "${testfile}"
    fi

    # let the containers out of the cage
    open_cage "${syncfile}"
  else
    wait_in_cage "${NSID}" "${syncfile}"

    ./"${testfile}" 1>/dev/null

    ctr=$(grep -c "${testfile}" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
    if [ "${ctr}" -ne "${i}" ]; then
      if [ "${reported}" -eq 0 ]; then
        echo " Error in ns ${NSID} round ${i}: Could not find ${i} measurement(s), found ${ctr}."
        reported=1
        if [ ! -f "${FAILFILE}" ]; then
          echo > "${FAILFILE}"
          cat -n "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
        fi
      fi
    fi

    filehash="$(hash_file "${imahash}" "${testfile}")"
    ctr=$(grep -c "${filehash}" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
    if [ "${ctr}" -ne 1 ]; then
      if [ "${reported}" -eq 0 ]; then
        echo " Error in ns ${NSID}: Could not find hash ${filehash} in measurement(s)."
        reported=1
        if [ ! -f "${FAILFILE}" ]; then
          echo > "${FAILFILE}"
          cat -n "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
        fi
      fi
    fi
  fi

  i=$((i + 1))
done
