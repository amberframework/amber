CRYSTAL_BIN ?= $(shell which crystal)

build:
	mkdir bin
	$(CRYSTAL_BIN) build --release -o bin/kgen src/kemalyst-generator.cr

clean:
	rm -f ./bin/kgen

install: build
