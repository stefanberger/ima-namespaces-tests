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
  securitfs|audit|measure|appraise|hash|selinux|evm) # securityfs is needed by all
    [ ! -d "${MNT}" ] && mkdir "${MNT}"
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

      # Also EVM files must be inaccessible
      p="${MNT}/integrity/evm"
      if [ -d "${p}" ]; then
        for f in "${p}/"*; do
          [ "${f}" = "${p}/active" ] && continue
          if cat "${f}" 2>/dev/null; then
            echo " Error: Should not be able to access file ${f}"
          fi
        done
      fi

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
  vtpm)
    mkdir "${MNT}" 2>/dev/null
    if ! msg=$(mount -t securityfs "${MNT}" "${MNT}" 2>&1); then
      rc=1
    else
      start_swtpm_chardev "0" "${VTPM_DEVICE_FD}" --tpm2
      if ! vtpm-exec --connect-to-ima-ns "${VTPM_DEVICE_FD}" 2>/dev/null; then
        rc=1
      fi
    fi
    ;;
  selftest)
    rc=90
    ;;
  esac
fi

# Check whether IMA-ns support audit or measure(+audit) or appraise+(measure+audit)
# and SELinux labels
if [ "${rc}" -eq 0 ]; then
  case "$1" in
  securitfs) ;;
  audit)
    # Audit was supported first
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
  hash)
    if ! printf "hash func=FILE_CHECK\n" > "${MNT}/ima/policy"; then
      rc=1
    fi
    ;;
  selinux)
    if ! printf "measure func=BPRM_CHECK subj_type=bin_t\n" > "${MNT}/ima/policy"; then
      rc=1
    fi
    ;;
  evm)
    # EVM is
    if [ ! -d "${MNT}/integrity/evm" ]; then
      rc=1
    fi
    ;;
  esac
fi

umount "${MNT}" 2>/dev/null

exit "${rc}"
