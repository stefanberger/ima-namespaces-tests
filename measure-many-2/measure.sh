#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059

#set -x

. ./ns-common.sh

SELF="$0"

MAXDEPTH=${MAXDEPTH:-32}                # maximum 32
POLICYDEPTH=${POLICYDEPTH:-${MAXDEPTH}} # up to which level to create a policy

[ -z "${DEPTH}" ] && { exit 1 ; }

MNT="./mnt-${DEPTH}"

if [ "${DEPTH}" -le "${POLICYDEPTH}" ]; then
  mkdir -p "${MNT}"

  mnt_securityfs "${MNT}"

  policy='measure func=BPRM_CHECK mask=MAY_EXEC uid=0 '

  echo "${policy}" > "${MNT}/ima/policy" || {
    echo " Error at depth ${DEPTH}: Could not set measure policy. Does IMA-ns support IMA-measurement?"
    exit "${SKIP:-3}"
  }

  nspolicy=$(busybox2 cat "${MNT}/ima/policy")
  if [ "${policy}" != "${nspolicy}" ]; then
    echo " Error at depth ${DEPTH}: Bad policy in namespace."
    echo "expected: |${policy}|"
    echo "actual  : |${nspolicy}|"
    exit "${FAIL:-1}"
  fi
fi

./bin/busybox2 echo "depth: $DEPTH" 1>/dev/null
# Modify busybox2 so we always will get a new measurement in all parent namespaces that have a policy
echo >> ./bin/busybox2

if [ "${DEPTH}" -lt "${MAXDEPTH}" ]; then
  SUCCESS=${SUCCESS:-0} FAIL=${FAIL:-1} SKIP=${SKIP:-3} \
    PATH=$PATH DEPTH=$((DEPTH + 1)) MAXDEPTH=${MAXDEPTH} POLICYDEPTH=${POLICYDEPTH} \
    unshare --user --map-root-user --mount --pid --fork "${SELF}"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    exit "${rc}"
  fi
fi

if [ "${DEPTH}" -le "${POLICYDEPTH}" ]; then
  ctr=$(grep -c busybox2 "${MNT}/ima/ascii_runtime_measurements")
  expected=$((MAXDEPTH - DEPTH + 1))
  if [ "${ctr}" -ne "${expected}" ]; then
    echo " Error at depth ${DEPTH}: Could not find ${expected} measurement(s) of busybox2 in container, found ${ctr}."
    exit "${FAIL:-1}"
  fi
  # echo " At depth ${DEPTH}: Found ${expected} measurements of busybox2"
fi

exit "${SUCCESS:-0}"
