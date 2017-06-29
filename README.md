![Amber Crystal Framework](https://github.com/Amber-Crystal/amber/blob/master/media/amber.png)

[![Gitter](https://img.shields.io/gitter/room/Amber-Crystal/Lobby.svg)](https://gitter.im/Amber-Crystal/Lobby)  [![Travis](https://img.shields.io/travis/Amber-Crystal/amber.svg)](https://travis-ci.org/Amber-Crystal/amber) [![license](https://img.shields.io/github/license/Amber-Crystal/amber.svg)](https://github.com/Amber-Crystal/amber/blob/master/LICENSE)  [![GitHub tag](https://img.shields.io/github/tag/Amber-Crystal/amber.svg)](https://github.com/Amber-Crystal/amber/releases/tag) [![Github All Releases](https://img.shields.io/github/downloads/Amber-Crystal/amber/total.svg)](https://github.com/Amber-Crystal/amber) [![Awesome](https://cdn.rawgit.com/sindresorhus/awesome/d7305f38d29fed78fa85652e3a63e154dd8e8829/media/badge.svg)](http://awesome-crystal.com/#awesome-crystal-web-frameworks) 
# Welcome to Amber

**Amber** is a web application framework written in [Crystal](http://www.crystal-lang.org) inspired by Kemal, Rails, Phoenix and other popular application frameworks.

The purpose of Amber is not to create yet another framework, but to take advantage of the beautiful Crystal language capabilities and provide engineers an efficient, cohesive, and well maintain web framework for the crystal community that embraces the language philosophies, conventions, and guides.

Amber Crystal borrows concepts that already have been battle tested, successful, and embrace new concepts through team and community collaboration and analysis, that aligns with Crystal philosophies.

## Amber Philosophy H.R.T.

*It's all about the community. Software development is a team sport!*

It's not enough to be brilliant when you're alone in your programming lair. You are not going to change the world or delight millions of users by hiding and preparing your secret invention. We need to work with other members, we need to share our visions, divide the labor, learn from others, we need to be a team.

**HUMILITY** We are not the center of the universe. You're neither omniscient nor infallible. You are open to self-improvement.

**RESPECT** You genuinely care about others you work with. You treat them as human beings and appreciate their abilities and accomplishments.

**TRUST** You believe others are competent and will do the right thing, and you are OK with letting them drive when appropriate.

## Become a Contributor

Contributing to Amber can be a rewarding way to learn, teach, and build experience in just about any skill you can imagine. You don’t have to become a lifelong contributor to enjoy participating in Amber.

Amber is a community effort and we want You to be part of ours [Join Amber Community!](https://github.com/Amber-Crystal/amber/blob/master/.github/CONTRIBUTING.md)

## Code of Conduct

We have adopted the Contributor Covenant to be our [CODE OF CONDUCT](CODE_OF_CONDUCT.md) guidelines for Amber.

## Have a Amber based project?

Use Amber badge ![Amber Framework](https://img.shields.io/badge/using-amber%20framework-orange.svg)

```markdown
[![Amber Framework](https://img.shields.io/badge/using-amber%20framework-orange.svg)](Your project url)
```

## Benchmark

Latest Results **968,824.35 requests per second: 32 cores at 2.7Ghz**

```bash
ubuntu@ip-172-31-0-70:~/bench⟫ wrk -d 60 -t 20 -c 1015 http://localhost:3000                                      
Running 1m test @ http://localhost:3000
  20 threads and 1015 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     1.86ms    2.88ms  56.61ms   87.54%
    Req/Sec    48.73k     6.01k   88.40k    68.28%
  58225168 requests in 1.00m, 4.01GB read
Requests/sec: 968824.35
Transfer/sec:     68.37MB
```

> Disclaimer: We share these benchmark results with the understanding they may vary depending on configurations and environment settings and by no means we are making any comparison claims with other web application frameworks.

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  amber:
    github: Amber-Crystal/amber
```

## Usage

Please see [Installing Amber CLI from the Amber Book](https://amber-crystal.gitbooks.io/amber/content/getting-started/installation/heroku.html)

## Contributing

1. Fork it (https://github.com/Amber-Crystal/amber)
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [eliasjpr](https://github.com/eliasjpr) Elias Perez - Maintainer
- [fridgerator](https://github.com/fridgerator) Nick Franken - Maintainer
- [elorest](https://github.com/elorest) Isaac Sloan - Maintainer
- [drujensen](https://github.com/drujensen) Dru Jensen - Maintainer
- [bew](https://github.com/bew) Benoit de Chezelles - Member

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

## Acknowledgments

* Inspired by Kemal, Rails, Phoenix
