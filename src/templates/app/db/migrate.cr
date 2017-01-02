require "kemalyst"
require "../src/models/*"

# Migrate will attempt to sync the sql_mapping definition in the model with
# the database schema.  This is always additive so you will not lose any data.
# Demo.migrate

# Prune will remove any columns from the database schema that are not defined
# in the sql_mapping.
# WARNING:  This will drop the columns not defined so you WILL lose data
# calling prune.  Make sure you have backed up or copied any data before
# calling this.
# Demo.prune
