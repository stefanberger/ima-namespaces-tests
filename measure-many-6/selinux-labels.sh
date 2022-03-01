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
    selinux_rules="measure func=BPRM_CHECK mask=MAY_EXEC subj_type=${SELINUX_LABEL} \n"
    selinux_rules="${selinux_rules}measure func=FILE_CHECK mask=MAY_READ obj_type=${SELINUX_LABEL} "
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

# Create a file (to be different for each namespace) and execute it
# while modifying it so that the policy in IMA needs to be accessed every time.
# Do this until a file with a given filename appears.
measure_loop()
{
  local donefile="$1"
  local create_file="$2"

  local myfile limit

  # only a subset does measurements
  limit=10
  [ "${NUM_CONTAINERS}" -gt "${limit}" ] && limit=$((NUM_CONTAINERS/20))

  myfile="myfile-${NSID}"

  # create the file with the SELinux label (module must be enabled)
  if [ "${create_file}" -eq 1 ] && [ "${NSID}" -le "${limit}" ]; then
    printf "#!/bin/sh\n echo " > "${myfile}"
    chmod 777 "${myfile}"
    setfattr -n security.selinux \
             -v "system_u:object_r:${SELINUX_LABEL}:s0" \
             "${myfile}"
  fi

  while [ ! -f "${donefile}" ]; do
    cat "/mnt/ima/policy" >/dev/null
    if [ "${NSID}" -le "${limit}" ]; then
      "./${myfile}" >/dev/null
      printf "a" >> "${myfile}"
    fi
    sleep 0.2
  done
}

stage=1
while [ "${stage}" -le 6 ]; do
  syncfile="${SYNCFILE}-${stage}"
  donefile="done"

  if [ "${NSID}" = "0" ]; then
    # control container
    wait_cage_full 0 "${syncfile}" "${NUM_CONTAINERS}"

    case "${stage}" in
    1) cmd="create-imans";;
    2) cmd="set-policy";;
    3) cmd="disabling-module"; rm -f "${donefile}";;
    4) cmd="check-policy-no-label";;
    5) cmd="enabling-module"; rm -f "${donefile}";;
    6) cmd="check-policy-has-label";;
    esac

    [ -f "${FAILFILE}" ] && {
      cmd="end"
      /usr/sbin/semodule -e "${SELINUX_MODULE}"
    }

    echo "Stage: ${stage}   cmd: ${cmd}"

    printf "${cmd}" > "${CMDFILE}"
    open_cage "${syncfile}"

    case "${cmd}" in
    disabling-module)
      echo "disabling module"
      time /usr/sbin/semodule -d "${SELINUX_MODULE}"
      sleep 1
      echo > "${donefile}"
      ;;
    enabling-module)
      echo "enabling module"
      time /usr/sbin/semodule -e "${SELINUX_MODULE}"
      sleep 1
      echo > "${donefile}"
      ;;
    esac
  else
    # testing container
    wait_in_cage "${NSID}" "${syncfile}"

    cmd="$(cat "${CMDFILE}")"
    #echo "cmd=|${cmd}|"

    case "${cmd}" in
    create-imans)           create_imans;;
    set-policy)             set_policy;;
    disabling-module)
                            measure_loop \
                             "${donefile}" \
                             "1";;
    enabling-module)
                            measure_loop \
                             "${donefile}" \
                             "0";;
    check-policy-no-label)  check_policy_no_label;;
    check-policy-has-label) check_policy_has_label;;
    end)                    break;;
    esac
  fi
  stage=$((stage+1))
done
