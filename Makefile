OUT_DIR=bin
PREFIX ?=/usr/local

all: build force_link

install: build
	@mkdir -p $(PREFIX)/bin
	cp `pwd`/bin/amber  $(PREFIX)/bin/amber

build:
	@echo "Building amber in $(shell pwd)"
	@mkdir -p `pwd`/$(OUT_DIR)
	@crystal build -o `pwd`/$(OUT_DIR)/amber src/amber/cli.cr -p --no-debug

run:
	`pwd`/$(OUT_DIR)/amber

clean:
	rm -rf `pwd`/$(OUT_DIR) .crystal .shards libs lib

link:
	@ln -s ./bin/amber $(PREFIX)/bin/amber

force_link:
	@echo "Symlinking `pwd`/bin/amber to $(PREFIX)/bin/amber"
	@ln -sf `pwd`/bin/amber $(PREFIX)/bin/amber
