PREFIX=/usr/local
INSTALL_DIR=$(PREFIX)/bin
AMBER_SYSTEM=$(INSTALL_DIR)/amber

OUT_DIR=$(shell pwd)/bin
AMBER=$(OUT_DIR)/amber
AMBER_SOURCES=$(shell find src/ -type f -name '*.cr')

all: build

build: lib $(AMBER)

lib:
	@crystal deps

$(AMBER): $(AMBER_SOURCES) | $(OUT_DIR)
	@echo "Building amber in $@"
	@crystal build -o $@ src/amber/cli.cr -p --no-debug

$(OUT_DIR) $(INSTALL_DIR):
	 @mkdir -p $@

run:
	$(AMBER)

install: build | $(INSTALL_DIR)
	@rm -f $(AMBER_SYSTEM)
	@cp $(AMBER) $(AMBER_SYSTEM)

link: build | $(INSTALL_DIR)
	@echo "Symlinking $(AMBER) to $(AMBER_SYSTEM)"
	@ln -s $(AMBER) $(AMBER_SYSTEM)

force_link: build | $(INSTALL_DIR)
	@echo "Symlinking $(AMBER) to $(AMBER_SYSTEM)"
	@ln -sf $(AMBER) $(AMBER_SYSTEM)

clean:
	rm -rf $(AMBER)

distclean:
	rm -rf $(AMBER) .crystal .shards libs lib
