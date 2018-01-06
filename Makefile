OUT_DIR=$(shell pwd)/bin
PREFIX=/usr/local

all: build

build: lib $(OUT_DIR)/amber

$(OUT_DIR)/amber:
	@echo "Building amber in $(shell pwd)"
	@mkdir -p $(OUT_DIR)
	@crystal build -o $(OUT_DIR)/amber src/amber/cli.cr -p --no-debug

lib:
	@crystal deps

install: build
	@mkdir -p $(PREFIX)/bin
	@rm $(PREFIX)/bin/amber
	@cp $(OUT_DIR)/amber $(PREFIX)/bin/amber

run:
	$(OUT_DIR)/amber

link: build
	@echo "Symlinking $(OUT_DIR)/amber to $(PREFIX)/bin/amber"
	@ln -s $(OUT_DIR)/amber $(PREFIX)/bin/amber

force_link: build
	@echo "Symlinking $(OUT_DIR)/amber to $(PREFIX)/bin/amber"
	@ln -sf $(OUT_DIR)/amber $(PREFIX)/bin/amber

clean:
	rm -rf $(OUT_DIR) .crystal .shards libs lib
