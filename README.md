# Tests for IMA Namespaces

This projects hosts simple bash/busybox script-based tests for testing of various 
aspects of IMA namespaces, such as IMA-audit, IMA-measure, IMA-appraisal and running
several hundred IMA namespaces/containers in parallel to test the locking and other
aspects of IMA namespaces.

The test suite is based on several commonly available tools:
- unshare from util-linux 2.36.2
- nsenter
- busybox
- keyctrl
- getfattr/setfattr
- ldd

Some of the tests use features of the unshare tool that seem to be susceptible
to the version of the unshare tool being used. Please use the recommended
version, or one that is not too far away from it.

Some of the results of the tests are dependent on the IMA compile time options. Until we
figure out how to get a handle on all of them and deal with different results, please use
the following Linux kernel compile time options. Some of them may remain requirements in the
future for the testing to make any sense. If you know of one compile time option that
'doesn't matter' whether it is set, let me know and we can mark it as such.

```
CONFIG_IMA_NS=y
CONFIG_IMA=y
CONFIG_IMA_MEASURE_PCR_IDX=10
CONFIG_IMA_LSM_RULES=y
# CONFIG_IMA_TEMPLATE is not set
CONFIG_IMA_NG_TEMPLATE=y
# CONFIG_IMA_SIG_TEMPLATE is not set
CONFIG_IMA_DEFAULT_TEMPLATE="ima-ng"
# CONFIG_IMA_DEFAULT_HASH_SHA1 is not set
CONFIG_IMA_DEFAULT_HASH_SHA256=y
# CONFIG_IMA_DEFAULT_HASH_SHA512 is not set
CONFIG_IMA_DEFAULT_HASH="sha256"
CONFIG_IMA_WRITE_POLICY=y
CONFIG_IMA_READ_POLICY=y
CONFIG_IMA_APPRAISE=y
CONFIG_IMA_ARCH_POLICY=y
# CONFIG_IMA_APPRAISE_BUILD_POLICY is not set
CONFIG_IMA_APPRAISE_BOOTPARAM=y
CONFIG_IMA_APPRAISE_MODSIG=y
CONFIG_IMA_TRUSTED_KEYRING=y
CONFIG_IMA_KEYRINGS_PERMIT_SIGNED_BY_BUILTIN_OR_SECONDARY=y
CONFIG_IMA_BLACKLIST_KEYRING=y
CONFIG_IMA_LOAD_X509=y
CONFIG_IMA_X509_PATH="/etc/keys/x509_ima.der"
CONFIG_IMA_APPRAISE_SIGNED_INIT=y
CONFIG_IMA_MEASURE_ASYMMETRIC_KEYS=y
CONFIG_IMA_QUEUE_EARLY_BOOT_KEYS=y
CONFIG_IMA_SECURE_AND_OR_TRUSTED_BOOT=y
# CONFIG_IMA_DISABLE_HTABLE is not set
CONFIG_EVM=y
CONFIG_EVM_ATTR_FSUUID=y
# CONFIG_EVM_ADD_XATTRS is not set
CONFIG_EVM_LOAD_X509=y
CONFIG_EVM_X509_PATH="/etc/keys/x509_evm.der"
```

Also, for now, please don't set any policies on the host except for the
built-in ones. Other policies may interfere with the test results for
example in the number of results in the audit log.

The test suite works with the following boot command line parameters:

```
ima_policy=tcb ima_template=ima-sig
```

Other command lines may also work.

## Running the Tests

To run the tests do the following:

```
make
sudo ./imatest --testcases testcases --logfile /var/log/imatest.log --clear
```

After a test run have a look at the output file `/var/log/imatest.log`. Depending on the
IMA namespacing support of IMA-audit, IMA-measure etc., various tests may have been skipped.

Some of the tests, particularly those related to auditing that check the contents of the
audit log, require root rights. This is the reason for the `sudo` in the above command.
Many tests can be run as normal user.

### Running multiple instances of the Tests

To test that 'everything is holding up' it is possible to run multiple instances
of the test suite, each in a different terminal. The important part is that each
instance is using a different work directory and log file.
Beware though that the more instances are running concurrently the more likely
it is that timeouts occur or that auditing-test errors occur due to audit.log
rotation.

One terminal:
```
export I=1; for ((i=0;i<10;i++)); do \
  sudo IMA_TEST_WORKDIR=/var/lib/imatest-${I} ./imatest --testcases testcases --logfile /var/log/imatest-${I}.log --clear; \
  echo; \
done
```

Another one:
```
export I=2; for ((i=0;i<10;i++)); do \
  sudo IMA_TEST_WORKDIR=/var/lib/imatest-${I} ./imatest --testcases testcases --logfile /var/log/imatest-${I}.log --clear; \
  echo; \
done
```

Follow the logs:

```
tail -f /var/log/imatest-*.log
```


## Running Individual Tests

To run tests individually have a look at the entries in the `testcases` file.
An example for running a test individually is the following:

```
# You have to run make once
make
./measure-1/test.sh
```

## What do the Tests Cover?

Concerns for the testing are:
- General functionality
- Modification of shared files and correct handling inside container(s) that did not modify the file: modification of file, modification of file signature
- Many containers running concurrently

| Testcase        | What it Covers                                          |
|-----------------|---------------------------------------------------------|
| appraise-1      | o Key measurements, signed executables                  |
|                 | o Invalid signatures and re-signing of executables      |
|                 | o Re-appraisal of file in container after file modification by host |
|                 | o Re-appraisal of file in container signing with unknown key |
| appraise-2      | Re-appraisal of file in container after host signed file with key unknown to container |
| appraise-3      | Execution of unsigned file fails in container if parent container has appraise policy and succeeds once file is signed |
| appraise-4      | O_DIRECT usage and policy rule with missing or available permit_directio |
| appraise-5      | Only signed policy accepted after POLICY_CHECK rule has been set |
| appraise-6      | Testing of proper enforcement of appraisal policy rule with SETXATTR_CHECK and varying set of allowed hash algos |
| appraise-7      | Testing of setxattr success on files with proper ownership in namespace, failures on files without proper ownership in namespace |
| appraise-8      | Testing of BPRM_CHECK and MMAP_CHECK; test removal and restoring of signature on library |
| appraise-9      | Testing of BPRM_CHECK and MMAP_CHECK using different templates for logging |
| appraise-10     | Testing that a newly created session keyring with _ima keyring and new key does not allow to run an executable signed with this new key |
| appraise-many-1 | Concurrently running IMA namespaces with own keyrings appraise executables |
| appraise-many-2 | Concurrently running IMA namespaces test appraisal and re-appraisal of files after file and signature modifications |
| appraise-many-3 | Concurrently running IMA namespaces test appraisal and re-appraisal of files after file and signature modifications and signing with their own private key |
| appraise-many-4 | Concurrently running IMA namespaces test BPRM_CHECK AND MMAP_CHECK using different templates for logging; test removal and restoring of signature on library |
| audit-1         | Simple setting of audit policy rule and verifying that audit log gets messages from IMA namespace. Modification of executable causes new audit message. |
| audit-2         | Non-root users cannot set audit policy rules |
| audit-3         | Host modifies file that namespace must re-audit |
| audit-4         | Ensuring that host root can nsenter mount namespace and set and audit rule there |
| audit-many-1    | Concurrently running IMA namespaces auditing execution of a program and check host audit log for number of expected entries |
| audit+measure-1 | Measuring and auditing of file; re-measuring and re-auditing of file after file modification; causing of open_writes and ToMToU audit message |
| audit+measure-2 | Host modifies file that namespace must re-audit and re-measure |
| au+me+app-1     | Host modifies file that namespace must re-audit and re-measure and re-appraise |
| evm-1           | Check that security.evm cannot be written while EVM is not namespaced |
| evm-2           | Check that security.evm can be written and removed when EVM is namespaced and files' uid and gid are mapped |
| evm-3           | Test appraisal with IMA and EVM signaturs and failures when signatures are removed |
| evm-4           | Test evm_xattrs securityfs file and modification of file metadata (xattrs, mode etc.) to check execution prevention |
| evm-many-1      | Concurrently running IMA namespaces test appraisal with IMA and EVM signaturs and failures when signatures are removed |
| evm+overlayfs-1 | Test with overlayfs and HMAC |
| evm+overlayfs-2 | Test with overlayfs and portable RSA signatures |
| evm+overlayfs-3 | Test with overlayfs and portable RSA signatures with FILE_CHECK policy |
| hash-1          | Ensuring that a xattr hash is generated on a file following hash policy rule |
| hash-2          | Ensuring that a xattr hash is generated on a file following hash policy rule and that the host, that has no hash rule, will not modify the hash |
| measure-1       | Measuring of an executed file and re-measuring after modification of the file|
| measure-2       | Configure namespace with hash algorithm and template |
| measure-3       | Verification that uid/gid values when viewed from another user namespace are showing expected values relative to that user namespace |
| measure-4       | Ensuring that number of rules allowed by container is limited |
| measure-5       | Testing of BPRM_CHECK and MMAP_CHECK using different templates for logging |
| measure-many-1  | Concurrently running IMA namespaces measure an executable |
| measure-many-2  | Measurements taken in nested containers up to 32 user spaces deep; executable run in one container is also measured in parent containers|
| measure-many-3  | Concurrently running IMA namespaces measure many generated scripts and check log |
| measure-many-4  | One control container modifies a file that other containers are running and expecting new measurements in containers every time |
| measure-many-5  | Concurrently running IMA namespaces with different hash and template configurations repeatedly run an executable that's being modified |
| measure-many-6  | Concurrently running IMA namespaces test disabling and enabling of SELinux labels |
| measure-many-7  | Concurrently running IMA namespaces permanently modify 5 files and execute them |
| vtpm-1          | Check IMA measurement list against PCR_Extends; use TPM 1.2 (swtpm) |
| vtpm-2          | Check IMA measurement list against PCR_Extends; use TPM 2 (swtpm) |
| vtpm-many-1     | Concurrently running IMA namespaces with measurement policy; check IMA measurement list against PCR_Extends; use TPM 1.2 (swtpm) |
| vtpm-many-2     | Concurrently running IMA namespaces with measurement policy; check IMA measurement list against PCR_Extends; use TPM 2 (swtpm) |
| vtpm-many-3     | Concurrently running IMA namespaces with measurement policy using different PCRs; check IMA measurement list against PCR_Extends; use TPM 2 (swtpm) |
| selftest-1      | Checks return of error codes and availability of environment variables in scripts |

## Test cases for IMA on the host

It is also possible to test IMA on the host, however, there are some
limitations. Since different tests need different IMA policies it is
necessary for the host to reboot between tests. Tests for IMA appraisal
may need to be restricted to hosts running an SELinux policy so that
appraisal rules can be activated based on an SELinux label selector.

All IMA tests for the host can be run from the command line.
However, the host's IMA policy has to be either empty or completely
replaceable so that only the required rules are active.

To run the IMA host tests using a systemd service, that may reboot the host
multiple times to set different IMA policies, run the following command:

```
sudo make check
```

To prevent the host from running the IMA tests on the next reboot run the
following command:

```
sudo systemctl disable imatest
```

or

```
sudo make uninstall
```

The test results will be in /var/log/imatest.log

The test cases for the host are organized so that multiple tests that can
share the same policy are located in the same directory. This avoids
unnecessary reboots.

| Testcase                       | What it Covers                                                             |
|--------------------------------|----------------------------------------------------------------------------|
| host-audit+measure-1/test.sh   | Run and rename an executable and ensure it is not audited and logged again after renaming |
| host-audit+measure-2/test.sh   | Open a file as root and as user 'nobody' and check that the audit and measurement logs only contain an entry due to user 'nobody' |
| host-audit+measure-2/tomtou.sh | Cause a ToMToU audit log message when user 'nobody' opens are file for reading and writing |
| host-measure-1/test.sh         | Measuring an executed file |
| host-measure-1/test2.sh        | Re-measuring after modification of a file |
| host-measure-2/test.sh         | Testing of BPRM_CHECK and MMAP_CHECK using different templates for logging |
| host-ns-measure-1/test.sh      | The same file executed by multiple IMA-ns must be logged for each IMA-ns once on the host. Requires CONFIG_IMA_NS_LOG_CHILD_DUPLICATES=y |


## Test cases using User Mode Linux (UML)

For compiling UML Linux you have to use the provided config/config.uml as
Linux .config file so IMA is available and was built with the right options.
(`make ARCH=um -j$(nproc)`).

**Some** tests can also be run using User Model Linux (UML). In this mode the user
has to set the IMA_TEST_UML environment variable and have it point to the
UML 'linux' executable. Since the test cases are running in a chroot
environment and devices such as `/dev/null` have to be created for it using
`mknod`, it is necessary to run the UML tests as root. A list of supported
tests can be found in the file `uml-testcases`.

The following command line can be used to run UML tests. The UML `linux`
executable it assumed to be located at /usr/local/bin/linux.

```
sudo IMA_TEST_UML=/usr/local/bin/linux ./imatest --testcases uml-testcases --clear
```

To run a single test case use this command line in verbose mode:

```
sudo IMA_TEST_UML=/usr/local/bin/linux IMA_TEST_VERBOSE=1 ./host-measure-1/test.sh
```

The following test cases are supported:

| Testcase                       | What it Covers                                                             |
|--------------------------------|----------------------------------------------------------------------------|
| appraise-1/test.sh             | see above |
| appraise-5/test.sh             | - " - |
| appraise-6/test.sh             | - " - |
| appraise-9/test.sh             | - " - |
| evm-3/test.sh                  | - " - |
| evm-4/test.sh                  | - " - |
| evm+kernel-cmd-1/test.sh       | Test EVM HMAC creation when passing evm=fix on kernel command line |
| evm+overlayfs-1/test.sh        | - " - |
| evm+overlayfs-2/test.sh        | - " - |
| evm+overlayfs-3/test.sh        | - " - |
| hash-1/test.sh                 | - " - |
| host-measure-1/test.sh         | - " - |
| host-measure-1/test2.sh        | - " - |
| host-measure-2/test.sh         | - " - |
| host-audit+measure-1/test.sh   | - " - ; requires run-in-uml.sh |
| kernel-cmd-1/test.sh           | Pass different parameters to ima_hash=,ima_template=,ima_policy= boot parameters and check resulting log |
| kernel-cmd-2/test.sh           | Pass different parameters to ima_hash=,ima_template_fmt=,ima_policy= boot parameters and check resulting log |
| selftest-1/test.sh             | see above |

**Some** IMA-namespacing related test cases can also be run by UML.
In this case UML is started which then creates an IMA-namespace to run the
test case. A list of supported tests can be found in the file `uml-ns-testcases`.

```
sudo IMA_TEST_UML=/usr/local/bin/linux IMA_TEST_ENV=container ./imatest --testcases uml-ns-testcases --clear
```

To run a single test case in verbose mode use this command line:

```
sudo IMA_TEST_UML=/usr/local/bin/linux IMA_TEST_ENV=container IMA_TEST_VERBOSE=1 ./host-measure-1/test.sh
```

Some of the tests have to be run with the run-in-uml.sh wrapper like this:

```
sudo IMA_TEST_UML=/usr/local/bin/linux IMA_TEST_ENV=container IMA_TEST_VERBOSE=1 ./run-in-uml.sh measure-4/test.sh
```

Note that you must always set the `IMA_TEST_UML` and `IMA_TEST_ENV=container`
environment variables to run UML tests for containers.

The following namespacing-related test cases are supported:

| Testcase                       | What it Covers                                                             |
|--------------------------------|----------------------------------------------------------------------------|
| appraise-1/test.sh             | see above |
| appraise-5/test.sh             | - " - |
| appraise-6/test.sh             | - " - |
| appraise-8/test.sh             | - " - |
| appraise-9/test.sh             | - " - |
| appraise-10/test.sh            | - " - |
| evm-3/test.sh                  | - " - |
| evm-4/test.sh                  | - " - |
| hash-1/test.sh                 | - " - |
| selftest-1/test.sh             | - " - |
| measure-1/test.sh              | - " - ; requires run-in-uml.sh |
| measure-4/test.sh              | - " - ; requires run-in-uml.sh |
| measure-many-1/test.sh         | - " - ; requires run-in-uml.sh |
| measure-many-2/test.sh         | - " - ; requires run-in-uml.sh |
| measure-many-3/test.sh         | - " - ; requires run-in-uml.sh |
| measure-many-4/test.sh         | - " - ; requires run-in-uml.sh |
| measure-many-5/test.sh         | - " - ; requires run-in-uml.sh |
| measure-many-7/test.sh         | - " - ; requires run-in-uml.sh |
