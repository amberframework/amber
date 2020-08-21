PREFIX=/usr/local
INSTALL_DIR=$(PREFIX)/bin
LAUNCH_SYSTEM=$(INSTALL_DIR)/launch

OUT_DIR=$(CURDIR)/bin
LAUNCH=$(OUT_DIR)/launch
LAUNCH_SOURCES=$(shell find src/ -type f -name '*.cr')

all: build

build: lib $(LAUNCH)

lib:
	@shards install --production

$(LAUNCH): $(LAUNCH_SOURCES) | $(OUT_DIR)
	@echo "Building launch in $@"
	@crystal build -o $@ src/launch/cli.cr -p --no-debug

$(OUT_DIR) $(INSTALL_DIR):
	 @mkdir -p $@

run:
	$(LAUNCH)

install: build | $(INSTALL_DIR)
	@rm -f $(LAUNCH_SYSTEM)
	@cp $(LAUNCH) $(LAUNCH_SYSTEM)

link: build | $(INSTALL_DIR)
	@echo "Symlinking $(LAUNCH) to $(LAUNCH_SYSTEM)"
	@ln -s $(LAUNCH) $(LAUNCH_SYSTEM)

force_link: build | $(INSTALL_DIR)
	@echo "Symlinking $(LAUNCH) to $(LAUNCH_SYSTEM)"
	@ln -sf $(LAUNCH) $(LAUNCH_SYSTEM)

clean:
	rm -rf $(LAUNCH)

distclean:
	rm -rf $(LAUNCH) .crystal .shards libs lib
