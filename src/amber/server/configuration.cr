module Amber
  module Configuration
    macro included
      protected def self.instance
        @@instance ||= new(Amber.settings)
      end

      def self.start
        instance.run
      end

      # Configure should probably be deprecated in favor of settings.
      protected def self.configure
        with self yield settings
      end

      protected def self.settings
        instance.settings
      end

			protected def self.settings=(new_settings : Amber::Settings = Amber.settings)
        instance.settings = new_settings
      end

      protected def self.router
        instance.router
      end

      protected def self.handler
        instance.handler
      end
    end
  end
end
