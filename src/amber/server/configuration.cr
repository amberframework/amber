module Amber
  module Configuration
    macro included
      class_property settings : Amber::Settings = Amber::Environment.load(
		"./config/environments", (ARGV[0]? || ENV["AMBER_ENV"]? || "development")
	  )

      def self.instance
        @@instance ||= new
      end

      def self.configure
        with settings yield settings
      end

      def settings
        @@settings
      end

      def self.key_generator
        settings.key_generator
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
