# kemalyst-generator 
[![Build Status](https://travis-ci.org/TechMagister/kemalyst-generator.svg?branch=master)](https://travis-ci.org/TechMagister/kemalyst-generator)

Rails like command line for kemalyst

## Installation

You can build the `kgen` tool from source:
```shellsession
$ git clone git@github.com:TechMagister/kemalyst-generator.git
$ cd kemalyst-generator/
$ shards install
$ make
```

You should now have a bin/kgen file to run. 

You can symlink this to a more global location like /usr/local/bin to make it easier to use:

`$ ln -sf $(pwd)/bin/kgen /usr/local/bin/kgen`

Optionally, you can use homebrew to install.

```shellsession
$ brew tap drujensen/kgen
$ brew install kgen
```

## Usage

``` shell
$ ./bin/kgen --help
kgen [OPTIONS] SUBCOMMAND

Kemalyst Generator

Subcommands:
  console

Options:
  -h, --help     show this help
  -v, --version  show version
```

## Development

See opened issues.

## Contributing

1. Fork it ( https://github.com/TechMagister/kemalyst-generator/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [TechMagister](https://github.com/TechMagister) Arnaud Fernandés - creator, maintainer
- [drujensen](https://github.com/drujensen) Dru Jensen - contributor
