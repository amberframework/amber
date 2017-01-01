OUT_DIR=bin

all: build

build:
	@echo "Building kgen in $(shell pwd)"
	@mkdir -p $(OUT_DIR)
	@crystal build --release -o $(OUT_DIR)/kgen src/kemalyst-generator.cr

run:
	$(OUT_DIR)/kgen

clean:
	rm -rf  $(OUT_DIR) .crystal .shards libs lib
