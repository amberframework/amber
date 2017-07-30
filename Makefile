OUT_DIR=bin

all: build force_link

build:
	@echo "Building amber in $(shell pwd)"
	@mkdir -p $(OUT_DIR)
	@crystal build -o $(OUT_DIR)/amber src/amber_cmd.cr -p --no-debug

run:
	$(OUT_DIR)/amber

clean:
	rm -rf  $(OUT_DIR) .crystal .shards libs lib

link: 
	@ln -s `pwd`/bin/amber /usr/local/bin/amber

force_link: 
	@echo "Symlinking `pwd`/bin/amber to /usr/local/bin/amber"
	@ln -sf `pwd`/bin/amber /usr/local/bin/amber
