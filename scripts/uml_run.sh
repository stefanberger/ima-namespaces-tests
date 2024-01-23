#!/bin/bash

# SPDX-License-Identifier: BSD-2-Clause

# Setup the filesystem so that a test case can be run
# and run the test case passed via UML_SCRIPT.

# set -x

exit_test()
{
  local rc="$1"

  echo "$rc" >> __exitcode

  busybox poweroff -f
}

export PATH=/bin:/usr/bin

if ! mkdir /sys || \
   ! mount -t sysfs sysfs /sys || \
   ! mount -t proc proc /proc || \
   ! mount -t securityfs securityfs /sys/kernel/security/ || \
   ! ln -s /bin /usr/bin || \
   ! mkdir -p /dev/fd || \
   ! mkdir -p /var/log/audit; then
  echo "Error: Could not setup filesystem"
  exit_test 1
fi

# echo Running test script now: ${UML_SCRIPT}

rm -f __exitcode

auditd

"${UML_SCRIPT}"
exit_test "$?"
