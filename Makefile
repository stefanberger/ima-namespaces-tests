
INSTDIR ?= /usr/share/imatest

TESTDIRS = \
	host-audit+measure-1 \
	host-audit+measure-2 \
	host-measure-1 \
	host-measure-2 \
	host-ns-measure-1

DESTS := $(patsubst %,$(INSTDIR)/%,$(TESTDIRS))

$(INSTDIR)/% : % .FORCE
	mkdir -p $@
	cp -rH $</* $@

.FORCE:

all:
	make -C keys all
	make -C vtpm-exec all

clean:
	make -C keys clean

install: all $(DESTS)
	install -m 755 imatest /usr/bin/imatest
	install -m 644 imatest.service /usr/lib/systemd/system/imatest.service
	install -m 644 host-testcases $(INSTDIR)
	install -m 644 common.sh $(INSTDIR)
	install -m 644 ns-common.sh $(INSTDIR)
	install -m 644 uml_chroot.sh $(INSTDIR)
	install -m 644 check.sh $(INSTDIR)

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
	# Must pass shellcheck 0.7.2 or later
	shellcheck *.sh */*.sh imatest
	codespell *.sh */*.sh imatest *.md

.PHONY: .FORCE
