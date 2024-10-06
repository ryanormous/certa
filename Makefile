
.PHONY: all install uninstall reinstall

all:
	./bin/certa-env

install:
	./bin/certa-setup

uninstall:
	./bin/certa-teardown

reinstall:
	./bin/certa-teardown
	./bin/certa-setup

