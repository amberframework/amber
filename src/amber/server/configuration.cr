module Amber
  module Configuration
    macro included
      def self.instance
        @@instance ||= new(Amber.settings)
      end

      def self.start
        instance.run
      end

      # Configure should probably be deprecated in favor of settings.
      def self.configure
        with self yield settings
      end

      def self.settings
        instance.settings
      end

			def self.settings=(new_settings : Amber::Settings = Amber.settings)
        instance.settings = new_settings
      end

      def self.pubsub_adapter
        instance.pubsub_adapter.instance
      end

      def self.router
        instance.router
      end

      def self.handler
        instance.handler
      end
    end
  end
end
