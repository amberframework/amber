all: build force_link

build:
	@echo "Building amber in $(shell pwd)"
	@shards build -p --no-debug

run:
	bin/amber

clean:
	rm -rf bin .crystal .shards libs lib

link:
	@ln -s `pwd`/bin/amber /usr/local/bin/amber

force_link:
	@echo "Symlinking `pwd`/bin/amber to /usr/local/bin/amber"
	@ln -sf `pwd`/bin/amber /usr/local/bin/amber
