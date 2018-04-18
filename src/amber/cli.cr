require "cli"
require "./version"
require "./exceptions/*"
require "./environment"
require "./cli/commands"

{% if flag? :amber_release %}
  AMBER_SHARD_TARGET = :current_version
{% elsif flag? :amber_stable %}
  AMBER_SHARD_TARGET = :stable_branch
{% else %}
  AMBER_SHARD_TARGET = :master_branch
{% end %}

Amber::CLI::MainCommand.run ARGV
