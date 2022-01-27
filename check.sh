#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# Run this script in a user namespace to detect which features of
# IMA-ns, if any, are supported. Using parameters 'securityfs',
# 'audit' (IMA-audit), 'measure' (IMA-measure), and 'appraise'
# (IMA-appraise) to check whether the specific feature is available.

# set -x

. ./ns-common.sh

rc=0
MNT=_mnt

# Check whether IMA-ns is available at all
if [ "${rc}" -eq 0 ]; then
  case "$1" in
  securitfs|audit|measure|appraise|selinux) # securityfs is needed by all
    mkdir "${MNT}"
    if ! msg=$(mount -t securityfs "${MNT}" "${MNT}" 2>&1); then
      rc=1
    elif [ ! -d "${MNT}/ima" ]; then
      rc=1
    else
      # check that most files are inaccessible
      for f in \
          ascii_runtime_measurements policy \
          violations runtime_measurements_count; do
        cat "${MNT}/ima/${f}" 2>/dev/null && {
          echo " Error: Should not be able to access file ${f}"
          rc=1
          break
        }
      done
      # activate IMA namespace
      echo 1 > "${MNT}/ima/active"

      # check that all files are readable now
      for f in "${MNT}/ima/"*; do
        cat "${f}" >/dev/null || {
          echo " Error: Could not access file ${f}"
          rc=1
          break
        }
      done

    fi
    ;;
  esac
fi

# Check whether IMA-ns support audit or measure(+audit) or appraise+(measure+audit)
# and SELinux labels
if [ "${rc}" -eq 0 ]; then
  case "$1" in
  securitfs) ;;
  audit)
    if ! printf "audit func=BPRM_CHECK\n" > "${MNT}/ima/policy"; then
      rc=1
    fi
    ;;
  measure)
    if ! printf "measure func=BPRM_CHECK\n" > "${MNT}/ima/policy"; then
      rc=1
    fi
    ;;
  appraise)
    if ! printf "appraise func=BPRM_CHECK\n" > "${MNT}/ima/policy"; then
      rc=1
    fi
    ;;
  selinux)
    if ! printf "audit func=BPRM_CHECK subj_type=bin_t\n" > "${MNT}/ima/policy"; then
      rc=1
    fi
  esac
fi

umount "${MNT}" 2>/dev/null

exit "${rc}"
