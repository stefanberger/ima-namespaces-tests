#!/usr/bin/env bash

# If no IMA_TEST_WORKDIR is passed to this script then it will ensure that the
# test runs in its own IMA_TEST_WORKDIR not shared by any other test.
# In case of test failure this script keeps the created directory.

if [ -z "${IMA_TEST_WORKDIR}" ]; then
  export IMA_TEST_WORKDIR=$(mktemp -d --tmpdir ima-ns-test-XXXXXX)
  $@
  rc=$?
  if [ "$rc" -eq 0 ]; then
    rm -rf "${IMA_TEST_WORKDIR}"
  fi
else
  $@
  rc=$?
fi
exit $rc