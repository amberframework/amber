module Amber::Mailer
  # Abstract base class for email delivery backends.
  #
  # All delivery adapters must inherit from this class and implement the
  # `deliver` method. The adapter pattern allows swapping between different
  # email transport mechanisms (SMTP, in-memory for testing, third-party APIs)
  # without changing application code.
  #
  # ## Built-in Adapters
  #
  # - `MemoryAdapter` - Stores emails in memory for testing and development
  # - `SMTPAdapter` - Delivers emails via SMTP protocol
  #
  # ## Creating a Custom Adapter
  #
  # ```
  # class MyAPIAdapter < Amber::Mailer::DeliveryAdapter
  #   def deliver(email : Email) : DeliveryResult
  #     # Send via your preferred API
  #     response = MyEmailAPI.send(email)
  #     DeliveryResult.new(is_successful: response.ok?)
  #   end
  # end
  # ```
  abstract class DeliveryAdapter
    abstract def deliver(email : Email) : DeliveryResult
  end
end
