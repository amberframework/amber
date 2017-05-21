# kemalyst-generator
[![Build Status](https://travis-ci.org/kemalyst/kemalyst-generator.svg?branch=master)](https://travis-ci.org/kemalyst/kemalyst-generator)

Rails like command line for kemalyst

## Installation

You can build the `kgen` tool from source:
```shellsession
$ git clone git@github.com:kemalyst/kemalyst-generator.git
$ cd kemalyst-generator/
$ shards install
$ make
```

You should now have a bin/kgen file to run.

You can symlink this to a more global location like /usr/local/bin to make it easier to use:

`$ ln -sf $(pwd)/bin/kgen /usr/local/bin/kgen`

Optionally, you can use homebrew to install.

```shellsession
$ brew tap kemalyst/kgen
$ brew install kgen
```

## Commands

``` shell
$ ./bin/kgen --help
kgen [OPTIONS] SUBCOMMAND

Kemalyst Generator

Subcommands:
  c         alias for console
  console
  g         alias for generate
  generate
  i         alias for init
  init
  m         alias for migrate
  migrate
  w         alias for watch
  watch

Options:
  -h, --help     show this help
  -v, --version  show version
```

## Usage

```sh
kgen init app [your_app] -d [pg | mysql | sqlite] -t [slang | ecr] --deps 
cd [your_app]
```
options: `-d` defaults to pg. `-t` defaults to slang. `--deps` will run `crystal deps` for you.

This will generate a traditional web application:
 - /config - Application and HTTP::Handler config's goes here.  The database.yml and routes.cr are here.
 - /lib - shards are installed here.
 - /public - Default location for html/css/js files.  The static handler points to this directory.
 - /spec - all the crystal specs go here.
 - /src - all the source code goes here.


Generate scaffolding for a resource:
```sh
kgen generate scaffold Post name:string body:text draft:bool
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

### Run Locally
To test the demo app locally:

1. Create a new Postgres or Mysql database called `[your_app]_development`
2. Configure your database with one of the following ways.
  * Add it in `config/database.yml`
  * Run `export DATABASE_URL=postgres://[username]:[password]@localhost:5432/[your_app]_development` which overrides the `config/database.yml`.
3. Migrate the database: `kgen migrate up`. You should see output like `
Migrating db, current version: 0, target: [datetimestamp]
OK   [datetimestamp]_create_shop.sql`
4. Run the specs: `crystal spec`
5. Start your app: `kgen watch`
6. Then visit `http://0.0.0.0:3000/`

Note: The `kgen watch` command uses [Sentry](https://github.com/samueleaton/sentry) to watch for any changes in your source files, recompiling automatically.

If you don't want to use Sentry, you can compile and run manually:

1. Build the app `crystal build --release src/[your_app].cr`
2. Run with `./[your_app]`
3. Visit `http://0.0.0.0:3000/`


## Development

See opened issues.

## Contributing

1. Fork it ( https://github.com/kemalyst/kemalyst-generator/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [TechMagister](https://github.com/TechMagister) Arnaud Fernandés - creator, maintainer
- [drujensen](https://github.com/drujensen) Dru Jensen - contributor
