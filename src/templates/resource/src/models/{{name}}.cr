require "kemalyst-model/adapter/pg"

class Demo < Kemalyst::Model
  adapter pg

  # id, created_at and updated_at columns are automatically created for you.
  sql_mapping({
    name:        ["VARCHAR UNIQUE NOT NULL", String],
    description: ["TEXT", String],
  })

  validate "Length of name should be greater than 3", ->(this : Demo) do
    if name = this.name
      return name.size > 3
    else
      return false
    end
  end

  def last_updated
    last_updated = updated_at
    if last_updated.is_a?(Time)
      formatter = Time::Format.new("%B %d, %Y")
      last_updated = formatter.format(last_updated)
    end
    return last_updated
  end
end
