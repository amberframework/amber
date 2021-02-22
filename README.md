![amber](https://github.com/amberframework/site-assets/raw/master/images/amber-horizontal.png)

**Productivity. Performance. Happiness.**

_Amber makes building web applications fast, simple, and enjoyable - with fewer bugs and blazing fast performance._

[![Build Status](https://travis-ci.org/amberframework/amber.svg?branch=master)](https://travis-ci.org/amberframework/amber)
[![Version](https://img.shields.io/github/tag/amberframework/amber.svg?maxAge=360&label=version)](https://github.com/amberframework/amber/releases/latest)
[![License](https://img.shields.io/github/license/amberframework/amber.svg)](https://github.com/amberframework/amber/blob/master/LICENSE)

[![Liberapay patrons](https://img.shields.io/liberapay/patrons/amber-framework.svg?label=liberapay%20patrons)](https://liberapay.com/amber-framework/)
[![Gitter](https://img.shields.io/gitter/room/amberframework/amber.svg)](https://gitter.im/amberframework/amber)

# Welcome to Amber

**Amber** is a web application framework written in [Crystal](https://crystal-lang.org/) inspired by Kemal, Rails, Phoenix and other popular application frameworks.

The purpose of Amber is not to create yet another framework, but to take advantage of the beautiful Crystal language capabilities and provide engineers and the Crystal community with an efficient, cohesive, well maintained web framework that embraces the language philosophies, conventions, and guidelines.

Amber borrows concepts that have already been battle tested and successful, and embraces new concepts through team and community collaboration and analysis, which also aligns with Crystal's philosophy.

## Community

Questions? Join our IRC channel [#amber](https://webchat.freenode.net/?channels=#amber) or [Gitter room](https://gitter.im/amberframework/amber) or ask on Stack Overflow under the [amber-framework](https://stackoverflow.com/questions/tagged/amber-framework) tag.

Guidelines? We have adopted the Contributor Covenant to be our [CODE OF CONDUCT](.github/CODE_OF_CONDUCT.md) for Amber.

Our Philosophy? [Read Amber Philosophy H.R.T.](.github/AMBER_PHILOSOPHY.md)

## Documentation

Read Amber documentation on https://docs.amberframework.org

## Benchmarks

[Techempower Framework Benchmarks - Round 18 (2019-07-09)](https://www.techempower.com/benchmarks/#section=data-r18&hw=ph&test=json&c=6&d=9&o=e)

* Filtered by Full Stack, Full ORM, Mysql or Pg for comparing similar frameworks.

## Installation & Usage

#### macOS

```
brew tap amberframework/amber
brew install amber
```

#### Linux

```
git clone https://github.com/amberframework/amber.git
cd amber
git checkout stable
make
sudo make install
```

If you're using ArchLinux or similar distro try:

```
yay -S amber
```

#### Common

To compile a local `bin/amber` per project use `shards build amber`

To use it as dependency, add this to your application's `shard.yml`:

```yaml
dependencies:
  amber:
    github: amberframework/amber
```

[Read Amber quick start guide](https://docs.amberframework.org/amber/getting-started)

[Read Amber CLI commands usage](https://docs.amberframework.org/amber/cli)

[Read more about Amber CLI installation guide](https://docs.amberframework.org/amber/guides/installation)

## Have an Amber-based Project?

Use Amber badge

[![Amber Framework](https://img.shields.io/badge/using-amber_framework-orange.svg)](https://amberframework.org/)

```markdown
[![Amber Framework](https://img.shields.io/badge/using-amber_framework-orange.svg)](https://amberframework.org/)
```
## Release Checklist

- Test and release all dependencies
- Test everything locally
- Run `crelease 0.36.0`
- repoint amber to master branch in `src/amber/cli/templates/app/shard.yml.ecr` template
- update release notes
- update homebrew version and sha
- update linux repositories
- build and deploy docker image:
  - verify Dockerfile is using the latest crystal version
  - `docker login`
  - `docker build -t amberframework/amber:0.36.0`
  - `docker push amberframework/amber:0.36.0`

## Contributing

Contributing to Amber can be a rewarding way to learn, teach, and build experience in just about any skill you can imagine. You don’t have to become a lifelong contributor to enjoy participating in Amber.

Tracking issues? Check our [project board](https://github.com/orgs/amberframework/projects/1?fullscreen=true).

Code Triage? Join us on [codetriage](https://www.codetriage.com/amberframework/amber).

[![Open Source Contributors](https://www.codetriage.com/amberframework/amber/badges/users.svg)](https://www.codetriage.com/amberframework/amber)

Amber is a community effort and we want You to be part of it. [Join Amber Community!](https://github.com/amberframework/amber/blob/master/.github/CONTRIBUTING.md)

1. Fork it https://github.com/amberframework/amber/fork
2. Create your feature branch `git checkout -b my-new-feature`
3. Write and execute specs and formatting checks `./bin/amber_spec`
4. Commit your changes `git commit -am 'Add some feature'`
5. Push to the branch `git push origin my-new-feature`
6. Create a new Pull Request

## Contributors

- [Dru Jensen](https://github.com/drujensen "drujensen")
- [Elias Perez](https://github.com/eliasjpr "eliasjpr")
- [Isaac Sloan](https://github.com/elorest "elorest")
- [Faustino Aguilar](https://github.com/faustinoaq "faustinoaq")
- [Nick Franken](https://github.com/fridgerator "fridgerator")
- [Mark Siemers](https://github.com/marksiemers "marksiemers")
- [Robert Carpenter](https://github.com/robacarp "robacarp")

[See more Amber contributors](https://github.com/amberframework/amber/graphs/contributors)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

## Acknowledgments

* Inspired by [Kemal](https://kemalcr.com/), [Rails](https://rubyonrails.org/), [Phoenix](https://phoenixframework.org/), and [Hanami](https://hanamirb.org/)
