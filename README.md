# Tests for IMA Namespaces

This projects hosts simple bash/busybox script-based tests for testing of various 
aspects of IMA namespaces, such as IMA-audit, IMA-measure, IMA-appraisal and running
several hundred IMA namespaces/containers in parallel to test the locking and other
aspects of IMA namespaces.

The test suite is based on several commonly available tools:
- unshare from util-linux 2.36.2
- busybox
- keyctrl
- getfattr/setfattr
- ldd

Some of the tests use features of the unshare tool that seem to be susceptible
to the version of the unshare tool being used. Please use the recommended
version, or one that is not too far away from it.

Some of the results of the tests are dependent on the IMA compile time options. Until we
figure out how to get a handle on all of them and deal with different results, please use
the following Linx kernel compile time options. Some of them may remain requirements in the
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

## Running the Tests

To run the tests do the following:

```
  make
  sudo ./imatest --testcases testcases --logfile /var/log/imatest.log --clear
```

Then have a look at the output file `/var/log/imatest.log`. Depending on the IMA namespacing
support of IMA-audit, IMA-measure etc., various tests may be skipped.
