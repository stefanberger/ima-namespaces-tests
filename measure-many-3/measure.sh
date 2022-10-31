#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059

# Caller must pass:
# NSID: distinct namespace id number
# NUMFILES: how many files to create
# FAILFILE: name of file to create upon failure
NSID=${NSID:-0}
FAILFILE=${FAILFILE:-failfile}

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

policy='measure func=BPRM_CHECK mask=MAY_EXEC uid=0 '

set_measurement_policy_from_string "${SECURITYFS_MNT}" "${policy}" "${FAILFILE}"

nspolicy=$(busybox2 cat "${SECURITYFS_MNT}/ima/policy")

ctr=$(grep -c busybox2 "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
if [ "${ctr}" -ne 1 ]; then
  echo " Error: Could not find 1 measurement of busybox2 in container, found ${ctr}."
  echo > "${FAILFILE}"
  exit "${FAIL:-1}"
fi

numfiles=${NUMFILES:-10}
loops=10

# Create numfiles scripts
i=0
while [ "${i}" -lt "${numfiles}" ]; do
  testfile="tf-${NSID}-${i}x"
  printf "#!/bin/env sh\necho " > "${testfile}"
  chmod 755 "${testfile}"
  i=$((i + 1))
done

# Run the files and modify each $loops times and run again
i=0
while [ "${i}" -lt "${numfiles}" ]; do
  testfile="tf-${NSID}-${i}x"

  j=0
  while [ "${j}" -lt "${loops}" ]; do
    ./"${testfile}" 1>/dev/null
    printf "a" >> "${testfile}"
    j=$((j + 1))
  done

  i=$((i + 1))
done

# Remove the test files and check that they were each recorded 10 times
i=0
while [ "${i}" -lt "${numfiles}" ]; do
  testfile="tf-${NSID}-${i}x"
  rm -f "${testfile}"
  ctr=$(grep -c "${testfile}" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
  if [ "${ctr}" -ne "${loops}" ]; then
    echo > "${FAILFILE}"
    echo " Error: COuld not find ${testfile} ${loops} times in measurement list, but ${ctr} times"
    exit "${FAIL:-1}"
  fi
  i=$((i + 1))
done

exit "${SUCCESS:-0}"
