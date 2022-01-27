#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3043
#set -x

. ./ns-common.sh
SYNCFILE=${SYNCFILE:-syncfile}

create_imans()
{
  mnt_securityfs "/mnt"
}

get_policy_string()
{
  local p1="$1"

  local selinux_rules=""

  if [ "${p1}" -eq 1 ]; then
    selinux_rules="audit func=BPRM_CHECK mask=MAY_EXEC subj_type=${SELINUX_LABEL} \n"
    selinux_rules="${selinux_rules}audit func=FILE_CHECK mask=MAY_READ obj_type=${SELINUX_LABEL} "
  fi
  echo "${selinux_rules}"
}

# Check that the policy shown by IMA is as expected
# @param1: label rules are there: 1
#          label rules are not there: 0
check_policy()
{
  local has_rules="$1"

  local policy tmp

  policy="$(get_policy_string "${has_rules}")"
  tmp="$(cat "/mnt/ima/policy")"
  if [ "${tmp}" != "$(printf "${policy}")" ]; then
    echo " Error: Unexpected policy in namespace"
    echo " expected: |${policy}|"
    echo " actual  : |${tmp}|"
    echo > "${FAILFILE}"
  fi
}

# Check that the policy has no rules with the SELinux label
check_policy_no_label()
{
  check_policy 0
}

# Check that the policy has the rules with the SELinux label
check_policy_has_label()
{
  check_policy 1
}

set_policy()
{
  local policy tmp

  policy="$(get_policy_string 1)"
  printf "${policy}" > "/mnt/ima/policy"
  check_policy_has_label
}

stage=1
while [ "${stage}" -lt 5 ]; do
  syncfile="${SYNCFILE}-${stage}"

  if [ "${NSID}" = "0" ]; then
    # control container
    wait_cage_full 0 "${syncfile}" "${NUM_CONTAINERS}"

    case "${stage}" in
    1) cmd="create-imans";;
    2) cmd="set-policy";;
    3) cmd="check-policy-no-label";echo "disabling module";/usr/sbin/semodule -d "${SELINUX_MODULE}";;
    4) cmd="check-policy-has-label";echo "enabling module";/usr/sbin/semodule -e "${SELINUX_MODULE}";;
    esac

    [ -f "${FAILFILE}" ] && {
      cmd="end"
      /usr/sbin/semodule -e "${SELINUX_MODULE}"
    }

    echo "Stage: ${stage}   cmd: ${cmd}"

    printf "${cmd}" > "${CMDFILE}"
    open_cage "${syncfile}"
  else
    # testing container
    wait_in_cage "${NSID}" "${syncfile}"

    cmd="$(cat "${CMDFILE}")"
    #echo "cmd=|${cmd}|"

    case "${cmd}" in
    create-imans)           create_imans;;
    set-policy)             set_policy;;
    check-policy-no-label)  check_policy_no_label;;
    check-policy-has-label) check_policy_has_label;;
    end)                    break;;
    esac
  fi
  stage=$((stage+1))
done
