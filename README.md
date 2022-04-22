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

Afer a test run have a look at the output file `/var/log/imatest.log`. Depending on the
IMA namespacing support of IMA-audit, IMA-measure etc., various tests may have been skipped.

Some of the tests, particularly those related to auditing that check the contents of the
audit log, require root rights. This is the reason for the `sudo` in the above command.
Many tests can be run as normal user.

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
| appraise-many-1 | Concurrently running IMA namespaces with own keyrings appraise executables |
| appraise-many-2 | Concurrently running IMA namespaces test appraisal and re-appraisal of files after file and signature modifications |
| appraise-many-3 | Concurrently running IMA namespaces test appraisal and re-appraisal of files after file and signature modifications and signing with their own private key |
| audit-1         | Simple setting of audit policy rule and verifying that audit log gets messages from IMA namespace. Modification of executable causes new audit message. |
| audit-2         | Non-root users cannot set audit policy rules |
| audit-3         | Host modifies file that namespace must re-audit |
| audit-4         | Ensuring that host root can nsenter mount namespace and set and audit rule there |
| audit-many-1    | Concurrently running IMA namespaces auditing execution of a program and check host audit log for number of expected entries |
| audit+measure-1 | Measuring and auditing of file; re-measuring and re-auditing of file after file modification; causing of open_writes and ToMToU audit message |
| audit+measure-2 | Host modifies file that namespace must re-audit and re-measure |
| au+me+app-1     | Host modifies file that namespace must re-audit and re-measure and re-appraise |
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
| vtpm-1          | Check IMA measurement list against PCR_Extends; use TPM 1.2 (swtpm) |
| vtpm-2          | Check IMA measurement list against PCR_Extends; use TPM 2 (swtpm) |
| vtpm-many-1     | Concurrently running IMA namespaces with measurement policy; check IMA measurement list against PCR_Extends; use TPM 1.2 (swtpm) |
| vtpm-many-2     | Concurrently running IMA namespaces with measurement policy; check IMA measurement list against PCR_Extends; use TPM 2 (swtpm) |
