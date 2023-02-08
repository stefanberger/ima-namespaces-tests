#!/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause

# shellcheck disable=SC2059,SC3028

# Create an _ima keyring under the session keyring and sign applications with a
# key (KEY) loaded onto that keyring (CERT). Then create a new session keyring
# along with another _ima keyring and load another key (CERT2) onto this new
# _ima keyring and sign an application with its key (KEY2) and test that this
# application does not run and therefore the new key (KEY2/CERT2) does not become
# valid. This is to ensure that IF there is an existing _ima keyring (created by
# container runtime for example) with a key loaded on it that this keyring cannot
# be 'overridden' through a new session keyring + _ima keyring and the user can
# put just any keys on it. If, however, there was no appraisal policy before the
# new session keyring was created then creating the new session keyring does allow
# loading keys onto the _ima keyring that IMA then ends up using.

. ./ns-common.sh

mnt_securityfs "${SECURITYFS_MNT}"

KEY=./rsakey.pem
CERT=./rsa.crt

# Key for 2nd script on new session keyring
KEY2=./rsakey2.pem
CERT2=./rsa2.crt

TESTFILE=/testfile

BUSYBOX=$(which busybox)
KEYCTL=$(which keyctl)

keyctl newring _ima @s >/dev/null 2>&1

if ! err=$(keyctl padd asymmetric "" %keyring:_ima < "${CERT}" 2>&1); then
  echo " Error: Could not load ${CERT} onto _ima keyring: ${err}"
  exit_test "${FAIL:-1}"
fi

# Sign evmctl to be able to use it later on
evmctl ima_sign --imasig --key "${KEY}" -a sha256 /usr/bin/evmctl >/dev/null 2>&1
if [ -z "$(getfattr -m ^security.ima -e hex --dump /usr/bin/evmctl 2>/dev/null)" ]; then
  echo " Error: security.ima should be there now. Is IMA appraisal support enabled?"
  # setting security.ima was only added when appraisal was enable
  exit_test "${FAIL:-1}"
fi

policy='appraise func=BPRM_CHECK mask=MAY_EXEC \n'

printf "${policy}" > "${SECURITYFS_MNT}/ima/policy" || {
  echo " Error: Could not set appraise policy. Does IMA-ns support IMA-appraise?"
  exit_test "${FAIL:-1}"
}

for tool in ${BUSYBOX} ${KEYCTL} /appraise-2nd.sh; do
  if ! err=$(evmctl ima_sign --imasig --key "${KEY}" -a sha256 "${tool}" 2>&1); then
     echo " Error: Could not sign ${tool}: ${err}"
     exit_test "${FAIL:-1}"
  fi
done

# Create a testfile with some random content
cat <<_EOF_ >"${TESTFILE}"
#!/bin/env sh

echo ${RANDOM}${RANDOM}
_EOF_
chmod 755 "${TESTFILE}"

# Check that unsigned file does not run
if "${TESTFILE}" 2>/dev/null; then
  echo " Error: Executing unsigned testfile must have failed"
  exit_test "${FAIL:-1}"
fi

TESTFILE=${TESTFILE} KEY=${KEY} CERT=${CERT} KEY2=${KEY2} CERT2="${CERT2}" \
  keyctl session - /appraise-2nd.sh
rc=$?
if [ $rc -ne 0 ]; then
  exit_test "${rc}"
fi

echo " INFO: Back in original script"

# Now it must run
if ! "${TESTFILE}" 1>/dev/null; then
  echo " Error: Executing testfile signed with good key (${KEY}) must work!"
  exit_test "${FAIL:-1}"
fi

exit_test "${SUCCESS:-0}"
