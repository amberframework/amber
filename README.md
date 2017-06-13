[![Build Status](https://travis-ci.org/Amber-Crystal/amber_cmd.svg?branch=master)](https://travis-ci.org/Amber-Crystal/amber_cmd)
# Amber::CMD
This section provides an introduction into Amber command-line interface. 

Amber provides a CLI client that makes interfacing with your file system and applications much smoother. The Amber console provides a framework for creating, generating, saffolding and running your Amber project.


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
brew tap amber-crystal/amber
brew install amber-crystal/amber/amber
```

## Commands

```shell
$ amber --help
amber [OPTIONS] SUBCOMMAND

Amber::CMD

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

1. Create a new Postgres or Mysql database called `[your_app]_development`
2. Configure your database in one of the following ways.
  * Add it in `config/database.yml`
  * Run `export DATABASE_URL=postgres://[username]:[password]@localhost:5432/[your_app]_development` 
    which overrides the `config/database.yml`.
3. Migrate the database: `amber migrate up`. You should see output like 
    `Migrating db, current version: 0, target: [datetimestamp]OK   [datetimestamp]_create_shop.sql`
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
