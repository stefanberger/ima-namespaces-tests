#!/bin/env sh

# shellcheck disable=SC2059

. ./ns-common.sh

mnt_securityfs "/mnt"

KEY=./rsakey.pem
CERT=./rsa.crt

keyctl newring _ima @s >/dev/null 2>&1
keyctl padd asymmetric "" %keyring:_ima < "${CERT}" >/dev/null 2>&1

policy='hash func=FILE_CHECK mask=MAY_READ \n'

printf "${policy}" > /mnt/ima/policy || {
  echo " Error: Could not set appraise+hash policy. Does IMA-ns support IMA-appraise and hash rules?"
  exit "${SKIP:-3}"
}

printf "Hello " >> testfile
# This cat here is necessary but the hash in security.ima does NOT show up yet
cat < testfile >/dev/null
getfattr -m ^security.ima -e hex --dump testfile

printf "world\n" >> testfile
# Now we must have the hash in security.ima
if [ -z "$(getfattr -m ^security.ima -e hex --dump testfile | grep ima)" ]; then
  echo " Error: File should have a hash now but it does NOT have one"
  exit "${FAIL:-1}"
fi

exit "${SUCCESS:-0}"
