#!/bin/sh

# This script copies the filesystem contents setup for UML
# into a loopback-mounted ext4-formatted filesystem that
# can then be used for a chroot or unshare environment.

exit_test()
{
  echo "$1" > ../__exitcode

  ./bin/busybox poweroff -f
}

cd "$(dirname "$0")" || exit_test 1

# We need to copy the filesystem into an image so UML can set xattrs
if [ ! -f .myimage ]; then
  if ! err=$(dd if=/dev/zero of=.myimage bs=1M count=100 2>&1); then
    echo "Error: dd failed: ${err}"
    exit_test 1
  fi

  if ! err=$(losetup -f .myimage --show); then
    echo "Error: losetup failed: ${err}"
    exit_test 1
  fi
  dev=${err}

  if ! err=$(mkfs.ext4 -b 4096 "${dev}" 2>&1); then
    echo "Error: mkfs.ext4 failed: ${err}"
    exit_test 1
  fi
else
  if ! err=$(losetup -f .myimage --show); then
    echo "Error: losetup failed: ${err}"
    exit_test 1
  fi
  dev=${err}
fi

if [ ! -d mntpoint ]; then
  if ! err=$(mkdir mntpoint 2>&1); then
    echo "Error: mkdir failed: ${err}"
    exit_test 1
  fi
fi

if ! err=$(mount -o i_version "${dev}" mntpoint 2>&1); then
  echo "Error: mount failed: ${err}"
  exit_test 1
fi

for f in *; do
  if [ "${f}" = "mntpoint" ]; then
    continue
  fi
  if [ ! -e "mntpoint/${f}" ]; then
    if ! err=$(cp -r "${f}" mntpoint 2>&1); then
      echo "Error: cp ${f} failed: ${err}"
      exit_test 1
    fi
  fi
done

if ! cd mntpoint; then
  echo "Error: 'cd mntpoint' failed"
  exit_test 1
fi

if [ ! -d dev ]; then
  if ! err=$(mkdir dev 2>&1); then
    echo "Error: 'mkdir dev' failed: ${err}"
    exit_test 1
  fi
fi

if [ ! -c dev/null ]; then
  if ! err=$(mknod dev/null c 1 3 2>&1); then
    echo "Error: mknod dev/null failed: ${err}"
    exit_test 1
  fi
fi

./bin/busybox rm -f __exitcode

mount -t proc proc /proc
"$@" \
  ${UML_SCRIPT:+${UML_SCRIPT}} \
  ${UML_SCRIPT_P1:+${UML_SCRIPT_P1}} \
  ${UML_SCRIPT_P2:+${UML_SCRIPT_P2}}

./bin/busybox cp __exitcode ..

./bin/busybox poweroff -f
