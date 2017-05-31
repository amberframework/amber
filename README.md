# amber_cmd
[![Build Status](https://travis-ci.org/Amber-Crystal/amber_cmd.svg?branch=master)](https://travis-ci.org/Amber-Crystal/amber_cmd)

Rails like command line for Amber

## Installation

You can build the `amber` tool from source:
```shellsession
$ git clone git@github.com:amber-crystal/amber_cmd.git
$ cd amber_cmd/
$ shards install
$ make
```

You should now be able to run `amber` in the command line.


Optionally, you can use homebrew to install.

```shellsession
#make this work
```

## Commands

``` shell
$ amber --help
amber [OPTIONS] SUBCOMMAND

Amber Cmd

Subcommands:
  c         alias for console
  console
  g         alias for generate
  generate
  n         alias for new
  new
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
amber new [your_app] -d [pg | mysql | sqlite] -t [slang | ecr] --deps 
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

### Run Locally
To test the demo app locally:

1. Create a new Postgres or Mysql database called `[your_app]_development`
2. Configure your database with one of the following ways.
  * Add it in `config/database.yml`
  * Run `export DATABASE_URL=postgres://[username]:[password]@localhost:5432/[your_app]_development` which overrides the `config/database.yml`.
3. Migrate the database: `amber migrate up`. You should see output like `
Migrating db, current version: 0, target: [datetimestamp]
OK   [datetimestamp]_create_shop.sql`
4. Run the specs: `crystal spec`
5. Start your app: `amber watch`
6. Then visit `http://0.0.0.0:3000/`

Note: The `amber watch` command uses [Sentry](https://github.com/samueleaton/sentry) to watch for any changes in your source files, recompiling automatically.

If you don't want to use Sentry, you can compile and run manually:

1. Build the app `crystal build --release src/[your_app].cr`
2. Run with `./[your_app]`
3. Visit `http://0.0.0.0:3000/`


## Development

See opened issues.

## Contributing

1. Fork it ( https://github.com/amber-crystal/amber_cmd/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors
- [elorest](https://github.com/elorest) Isaac Sloan - Creator, Maintainer
- [eliasjpr](https://github.com/eliasjpr) Elias Perez - Maintainer
- [fridgerator](https://github.com/fridgerator) Nick Franken - Maintainer
- [phoffer](https://github.com/phoffer) Paul Hoffer - Maintainer
- [bew](https://github.com/fridgerator) Benoit de Chezelles - Member
- [TechMagister](https://github.com/TechMagister) Arnaud Fernandés - Initial Creator of some borrowed code.
- [drujensen](https://github.com/drujensen) Dru Jensen - contributor
