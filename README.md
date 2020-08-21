![launch](https://github.com/launchframework/site-assets/raw/master/images/launch-horizontal.png)

**Productivity. Performance. Happiness.**

_Launch makes building web applications fast, simple, and enjoyable - with fewer bugs and blazing fast performance._

[![Build Status](https://travis-ci.org/launchframework/launch.svg?branch=master)](https://travis-ci.org/launchframework/launch)
[![Version](https://img.shields.io/github/tag/launchframework/launch.svg?maxAge=360&label=version)](https://github.com/launchframework/launch/releases/latest)
[![License](https://img.shields.io/github/license/launchframework/launch.svg)](https://github.com/launchframework/launch/blob/master/LICENSE)

[![Liberapay patrons](https://img.shields.io/liberapay/patrons/launch-framework.svg?label=liberapay%20patrons)](https://liberapay.com/launch-framework/)
[![Gitter](https://img.shields.io/gitter/room/launchframework/launch.svg)](https://gitter.im/launchframework/launch)

# Welcome to Launch

**Launch** is a web application framework written in [Crystal](https://crystal-lang.org/) inspired by Kemal, Rails, Phoenix and other popular application frameworks.

The purpose of Launch is not to create yet another framework, but to take advantage of the beautiful Crystal language capabilities and provide engineers and the Crystal community with an efficient, cohesive, well maintained web framework that embraces the language philosophies, conventions, and guidelines.

Launch borrows concepts that have already been battle tested and successful, and embraces new concepts through team and community collaboration and analysis, which also aligns with Crystal's philosophy.

## Community

Questions? Join our IRC channel [#launch](https://webchat.freenode.net/?channels=#launch) or [Gitter room](https://gitter.im/launchframework/launch) or ask on Stack Overflow under the [launch-framework](https://stackoverflow.com/questions/tagged/launch-framework) tag.

Guidelines? We have adopted the Contributor Covenant to be our [CODE OF CONDUCT](.github/CODE_OF_CONDUCT.md) for Launch.

Our Philosophy? [Read Launch Philosophy H.R.T.](.github/AMBER_PHILOSOPHY.md)

## Documentation

Read Launch documentation on https://docs.launchframework.org

## Benchmarks

[Techempower Framework Benchmarks - Round 18 (2019-07-09)](https://www.techempower.com/benchmarks/#section=data-r18&hw=ph&test=json&c=6&d=9&o=e)

* Filtered by Full Stack, Full ORM, Mysql or Pg for comparing similar frameworks.

## Installation & Usage

#### macOS

```
brew tap launchframework/launch
brew install launch
```

#### Linux

```
git clone https://github.com/launchframework/launch.git
cd launch
git checkout stable
make
sudo make install
```

If you're using ArchLinux or similar distro try:

```
yay -S launch
```

#### Common

To compile a local `bin/launch` per project use `shards build launch`

To use it as dependency, add this to your application's `shard.yml`:

```yaml
dependencies:
  launch:
    github: launchframework/launch
```

[Read Launch quick start guide](https://docs.launchframework.org/launch/getting-started)

[Read Launch CLI commands usage](https://docs.launchframework.org/launch/cli)

[Read more about Launch CLI installation guide](https://docs.launchframework.org/launch/guides/installation)

## Have an Launch-based Project?

Use Launch badge

[![Launchcr Framework](https://img.shields.io/badge/using-launch_framework-orange.svg)](https://launchframework.org/)

```markdown
[![Launchcr Framework](https://img.shields.io/badge/using-launch_framework-orange.svg)](https://launchframework.org/)
```

## Contributing

Contributing to Launch can be a rewarding way to learn, teach, and build experience in just about any skill you can imagine. You don’t have to become a lifelong contributor to enjoy participating in Launch.

Tracking issues? Check our [project board](https://github.com/orgs/launchframework/projects/1?fullscreen=true).

Code Triage? Join us on [codetriage](https://www.codetriage.com/launchframework/launch).

[![Open Source Contributors](https://www.codetriage.com/launchframework/launch/badges/users.svg)](https://www.codetriage.com/launchframework/launch)

Launch is a community effort and we want You to be part of it. [Join Launch Community!](https://github.com/launchframework/launch/blob/master/.github/CONTRIBUTING.md)

1. Fork it https://github.com/launchframework/launch/fork
2. Create your feature branch `git checkout -b my-new-feature`
3. Write and execute specs and formatting checks `./bin/launch_spec`
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

[See more Launch contributors](https://github.com/launchframework/launch/graphs/contributors)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

## Acknowledgments

* Inspired by [Kemal](https://kemalcr.com/), [Rails](https://rubyonrails.org/), [Phoenix](https://phoenixframework.org/), and [Hanami](https://hanamirb.org/)
