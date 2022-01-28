
INSTDIR ?= /usr/share/imatest

TESTDIRS = \
	appraise-1 \
	appraise-2 \
	appraise-3 \
	appraise-4 \
	appraise-many-1 \
	appraise-many-2 \
	audit-1 \
	audit-many-1 \
	audit+measure-1 \
	measure-1 \
	measure-many-1 \
	measure-many-2 \
	measure-many-3 \
	measure-many-4

DESTS := $(patsubst %,$(INSTDIR)/%,$(TESTDIRS))

$(INSTDIR)/% : % .FORCE
	@mkdir -p $@
	cp -r $< $@

.FORCE:

all:
	make -C keys all

clean:
	make -C keys clean

install: all $(DESTS)
	install -m 755 imatest /usr/bin/imatest
	install -m 644 imatest.service /usr/lib/systemd/system/imatest.service
	install -m 644 testcases $(INSTDIR)
	install -m 644 common.sh $(INSTDIR)

uninstall:
	rm -rf /usr/bin/imatest /usr/lib/systemd/system/imatest.service $(INSTDIR)

check: install
	@if test -f /etc/ima/ima-policy; then \
		echo "*** /etc/ima/ima-policy has to be removed first ***"; \
		exit 1; \
	fi
	rm -f /var/lib/imatest/.state
	systemctl enable imatest.service
	reboot

syntax-check:
	shellcheck *.sh */*.sh imatest

.PHONY: .FORCE
