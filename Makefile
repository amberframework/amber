CRYSTAL_BIN ?= $(shell which crystal)
CONTENT = "\#! /usr/bin/env sh\n\
echo 'Building kgen...'\n\
$(CRYSTAL_BIN) build --release -o bin/kgen lib/kemalyst-generator/src/kemalyst-generator.cr\n\
echo 'rerun ./bin/kgen'"

build:
	cd ../.. && mkdir -p bin && echo -e $(CONTENT) > bin/kgen && chmod +x bin/kgen
