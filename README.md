![Amber Framework](https://github.com/amberframework/amber/blob/master/media/amber.png)

[![Gitter](https://img.shields.io/gitter/room/amberframework/amber.svg)](https://gitter.im/amberframework/amber)
[![Travis](https://img.shields.io/travis/amberframework/amber.svg)](https://travis-ci.org/amberframework/amber)
[![license](https://img.shields.io/github/license/amberframework/amber.svg)](https://github.com/amberframework/amber/blob/master/LICENSE)
[![GitHub tag](https://img.shields.io/github/tag/amberframework/amber.svg)](https://github.com/amberframework/amber/releases/latest)
[![Awesome](https://cdn.rawgit.com/sindresorhus/awesome/d7305f38d29fed78fa85652e3a63e154dd8e8829/media/badge.svg)](https://github.com/veelenga/awesome-crystal/#web-frameworks)

# Welcome to Amber

**Amber** is a web application framework written in [Crystal](http://www.crystal-lang.org) inspired by Kemal, Rails, Phoenix and other popular application frameworks.

The purpose of Amber is not to create yet another framework, but to take advantage of the beautiful Crystal language capabilities and provide engineers an efficient, cohesive, and well maintained web framework for the crystal community that embraces the language philosophies, conventions, and guides.

Amber Crystal borrows concepts that already have been battle tested, successful, and embrace new concepts through team and community collaboration and analysis, that aligns with Crystal philosophies.

## Read the Docs

Documentation https://docs.amberframework.org


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

#### Linux

Ensure you have the necessary dependencies:

- `git`: Use your platform specific package manager to install `git`
- `crystal`: Follow the instructions to get `crystal` on this page: <https://crystal-lang.org/docs/installation/index.html>

##### For Debian & Ubuntu
- These are necessary to compile the CLI:
- `sudo apt-get install build-essential libreadline-dev libsqlite3-dev libpq-dev libmysqlclient-dev libssl-dev`

<!-- WIP: ##### For RedHat & CentOS
- `sudo yum groupinstall 'Development Tools' `
- `sudo yum install readline-devel sqlite-devel openssl-devel libyaml-devel gc-devel libevent-devel` -->

Once you have these dependencies, You can build the `amber` tool from source:


```shellsession
$ git clone git@github.com:amberframework/amber.git
$ cd amber/
$ shards install
$ make install
```

##### For ArchLinux & derivates
- Install the CLI from [AUR package](https://aur.archlinux.org/packages/amber/). Dependencies are automatically installed.
- `yaourt -S amber`

You should now be able to run `amber` in the command line.

#### Mac OS X

Best way to get `amber` on Mac OS X is via Homebrew:

```shellsession
$ brew install amberframework/amber/amber
```


Refer to [this link](https://brew.sh/) if you don't have homebrew installed.

## Amber CLI Commands

```shell
$ amber --help
amber [OPTIONS] SUBCOMMAND

Amber

The `amber new` command creates a new Amber application with a default
directory structure and configuration at the path you specify.

You can specify extra command-line arguments to be used every time
`amber new` runs in the .amber.yml configuration file in your project
root directory

Note that the arguments specified in the .amber.yml file does not affect the
defaults values shown above in this help message.

Usage:
amber new [app_name] -d [pg | mysql | sqlite] -t [slang | ecr] --deps

Commands:
  amber c console                 # Starts a amber console   
  amber g generate [SUBCOMMAND]   # Generate Amber classes
  amber n new                     # Generate a new amber project
  amber m migrate [SUBCOMMAND]    # Performs database migrations tasks
  amber w watch                   # Starts amber server and rebuilds on file changes
  amber routes                    # Prints the routes (In Development)
  amber r run [OPTION]            # Compiles and runs your project. Options: [-p --port | -e -environment]
  amber deploy [OPTION]           # Provisions server and deploys project. [-s --service | -k --key | -t --tag | -b --branch]
  amber encrypt [OPTION]          # Encrypts environment YAML file. [env | -e --editor | --noedit]

Options:
  -t, --template [name]           # Preconfigure for selected template engine. Options: slang | ecr
  -d, --database [name]           # Preconfigure for selected database. Options: pg | mysql | sqlite
  -h, --help                      # Describe available commands and usages
  -v, --version                   # Prints Amber version
  --deps                          # Installs project dependencies

Example:
  amber new ~/Code/Projects/weblog
  This generates a skeletal Amber installation in ~/Code/Projects/weblog.
```

## Usage

```sh
amber new [your_app] -d [pg | mysql | sqlite] -t [slang | ecr] --deps
cd [your_app]
```
options: `-d` defaults to pg. `-t` defaults to slang. `--deps` will run `crystal deps` for you.

This will generate a traditional web application:
 - **/config** - Application and HTTP::Handler config's goes here.  The database.yml and routes.cr are here.
 - **/lib** - shards are installed here.
 - **/public** - Default location for html/css/js files.  The static handler points to this directory.
 - **/spec** - all the crystal specs go here.
 - **/src** - all the source code goes here.

## Scaffolding
Generate scaffolding for a resource:
```sh
amber generate scaffold Post name:string body:text draft:bool
```

This will generate scaffolding for a Post:
 - src/controllers/post_controller.cr
 - src/models/post.cr
 - src/views/post/*
 - db/migrations/[datetimestamp]_create_post.sql
 - spec/controllers/post_controller_spec.cr
 - spec/models/post_spec.cr
 - appends route to config/routes.cr
 - appends navigation to src/layouts/_nav.slang

## Running App Locally
To test the generated App locally:

1. Make sure your app has the right credentials via the following methods: 
  * Add it in `config/database.yml`
  or
  * Run `export DATABASE_URL=postgres://[username]:[password]@localhost:5432/[your_app]_development`
    which overrides the `config/database.yml`.
2. Migrate the database: `amber db create migrate`. You should see output like
    `Migrating db, current version: 0, target: [datetimestamp]OK   [datetimestamp]_create_shop.sql`
3. Run the specs: `crystal spec`
4. Start your app: `amber watch`
5. Then visit `http://0.0.0.0:3000/`

Note: The `amber watch` command uses [Sentry](https://github.com/samueleaton/sentry) to watch for any changes in your source files, recompiling automatically.

If you don't want to use Sentry, you can compile and run manually:

1. Build the app `crystal build --release src/[your_app].cr`
2. Run with `./[your_app]`
3. Visit `http://0.0.0.0:3000/`


## Amber Philosophy H.R.T.

*It's all about the community. Software development is a team sport!*

It's not enough to be brilliant when you're alone in your programming lair. You are not going to change the world or delight millions of users by hiding and preparing your secret invention. We need to work with other members, we need to share our visions, divide the labor, learn from others, we need to be a team.

**HUMILITY** We are not the center of the universe. You're neither omniscient nor infallible. You are open to self-improvement.

**RESPECT** You genuinely care about others you work with. You treat them as human beings and appreciate their abilities and accomplishments.

**TRUST** You believe others are competent and will do the right thing, and you are OK with letting them drive when appropriate.

## Code of Conduct

We have adopted the Contributor Covenant to be our [CODE OF CONDUCT](.github/CODE_OF_CONDUCT.md) guidelines for Amber.

## Have a Amber based project?

Use Amber badge ![Amber Framework](https://img.shields.io/badge/using-amber%20framework-orange.svg)

```markdown
[![Amber Framework](https://img.shields.io/badge/using-amber%20framework-orange.svg)](Your project url)
```

## Contributing

Contributing to Amber can be a rewarding way to learn, teach, and build experience in just about any skill you can imagine. You don’t have to become a lifelong contributor to enjoy participating in Amber.

Amber is a community effort and we want You to be part of ours [Join Amber Community!](https://github.com/amberframework/amber/blob/master/.github/CONTRIBUTING.md)

1. Fork it ( https://github.com/amberframework/amber/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Amber Core Team

- [eliasjpr](https://github.com/eliasjpr) Elias Perez - Maintainer
- [fridgerator](https://github.com/fridgerator) Nick Franken - Maintainer
- [elorest](https://github.com/elorest) Isaac Sloan - Maintainer
- [drujensen](https://github.com/drujensen) Dru Jensen - Maintainer

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

## Acknowledgments

* Inspired by Kemal, Rails, Phoenix, Hanami
