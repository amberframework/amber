# kemalyst-generator

Rails like command line for kemalyst

## Installation

``` yaml
development_dependencies:
    kemalyst-generator:
        github: TechMagister/kemalyst-generator
        branch: master
```

## Usage

``` shell
./bin/kgen --help
kgen [OPTIONS] SUBCOMMAND

Kemalyst Generator

Subcommands:
  console

Options:
  -h, --help     show this help
  -v, --version  show version
```

## Development

TODO:
- [x] Basic console
- [ ] Import models, controllers when starting console
- [ ] Add Generator for models
- [ ] Add Generator for controllers
- [ ] Run database console accoding to config/database.yml
- [ ] Add database migration
- [ ] Run a sentry instance

## Contributing

1. Fork it ( https://github.com/TechMagister/kemalyst-generator/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [TechMagister](https://github.com/TechMagister) Arnaud Fernandés - creator, maintainer
