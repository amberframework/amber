macro contract(klass, key = "")
  def {{klass.id.downcase}}
    {{klass.id}}.instance(@raw_params, {{key.id.stringify}})
  end

  struct {{klass.id}}
    include Contract::Validation
    @raw_params : Amber::Router::Params

    def self.instance(raw_params, key)
      @@instance ||= new(raw_params, key)
    end

    {{yield}}
  end
end
