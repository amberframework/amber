module Amber
  module Configuration
    macro included
      property settings = Settings.new

      def self.instance
        @@instance ||= new
      end

      # Configure should probably be deprecated in favor of settings.
      def self.configure
        with settings yield settings
      end

      def self.settings(&block)
        with settings yield settings
      end

      def self.settings
        instance.settings
      end

      def self.secret_key_base
        settings.secret_key_base
      end

      def self.start
        instance.run
      end

      def self.log
        settings.log
      end

      def self.color
        settings.color
      end

      def self.pubsub_adapter
        settings.pubsub_adapter.instance
      end

      def self.router
        settings.router
      end

      def self.redis_url
        settings.redis_url
      end
    end
  end
end
