OUT_DIR=bin
PREFIX ?= /usr/local

all: build force_link

install: build
	sudo cp `pwd`/bin/amber $(PREFIX)/bin/amber

build:
	@echo "Building amber in $(shell pwd)"
	@mkdir -p $(OUT_DIR)
	@crystal build -o $(OUT_DIR)/amber src/amber/cli.cr -p --no-debug

run:
	$(OUT_DIR)/amber

clean:
	rm -rf  $(OUT_DIR) .crystal .shards libs lib

link:
	@ln -s `pwd`/bin/amber $(PREFIX)/bin/amber

force_link:
	@echo "Symlinking `pwd`/bin/amber to $(PREFIX)/bin/amber"
	@ln -sf `pwd`/bin/amber $(PREFIX)/bin/amber
