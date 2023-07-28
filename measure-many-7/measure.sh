#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3018,SC3020,SC3028

# Caller must pass:
# NSID: distinct namespace id number
# FAILFILE: name of file to create upon failure
# NUM_CONTAINERS: number of containers running
NSID=${NSID:-0}
FAILFILE=${FAILFILE:-failfile}

. ./ns-common.sh

cmdfile="cmdfile"
NUM_ITER=1000

stage=0

while [ "${stage}" -le 2 ]; do
  syncfile="syncfile-${stage}"
  cmdfile="cmdfile-${stage}"

  if [ "$NSID" -eq "0" ]; then
    # coordinator NSID==0 tells other containers what to do
    wait_cage_full "${NSID}" "${syncfile}" "${NUM_CONTAINERS}"

    echo "At stage: ${stage}"
    case "${stage}" in
    0) cmd="set-policy";;
    1) cmd="start";;
    2) cmd="end";;
    esac

    printf "${cmd}" > "${cmdfile}"

    # let the containers out of the cage
    open_cage "${syncfile}"
  else
    wait_in_cage "${NSID}" "${syncfile}"

    case "$(cat "${cmdfile}")" in
    set-policy)
      mnt_securityfs "${SECURITYFS_MNT}"
      policy="measure func=BPRM_CHECK mask=MAY_EXEC "
      printf "${policy}" > "${SECURITYFS_MNT}/ima/policy"
      if [ "${policy}" != "$(cat "${SECURITYFS_MNT}/ima/policy")" ]; then
        echo "ERROR: Could not set policy"
        echo 1 >> "${FAILFILE}"
      fi
      ;;
    start)
      i=0
      while [ "${i}" -lt "${NUM_ITER}" ]; do
        fn="testfile"$((RANDOM % 5))

        if [ "${NSID}" -eq 1 ] && [ "$((i % 100))" -eq 0 ]; then
          printf "  Iteration %5s/${NUM_ITER}\n" "${i}"
        fi

        case "$((RANDOM % 10))" in
        0)
          rm -f "${fn}" &>/dev/null
          ;;
        1|2|3|4|5|6|7|8|9)
          sh -c "(echo '#!/bin/env sh'; echo ${RANDOM}) >> ${fn}" 2>/dev/null
          chmod 755 "${fn}" 2>/dev/null
          sh -c ./${fn} 2>/dev/null
          ;;
        esac
        i=$((i + 1))
      done
      ;;
    end)
      num=$(grep -cE "/testfile" "${SECURITYFS_MNT}/ima/ascii_runtime_measurements")
      if [ "${num}" -eq 0 ]; then
        echo " Error: Could not find testfile measurements in log"
        cat "${SECURITYFS_MNT}/ima/ascii_runtime_measurements"
        echo 1 >> "${FAILFILE}"
      fi
      ;;
    esac
  fi

  stage=$((stage + 1))
done

exit "${SUCCESS:-0}"
