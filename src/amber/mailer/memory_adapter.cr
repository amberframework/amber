module Amber::Mailer
  # In-memory delivery adapter for testing and development.
  #
  # Stores all delivered emails in a thread-safe class-level array instead of
  # actually sending them. This allows tests to verify that emails were sent
  # with the correct content, recipients, and structure.
  #
  # ## Usage in Tests
  #
  # ```
  # # Clear any previously stored emails
  # Amber::Mailer::MemoryAdapter.clear
  #
  # # Deliver an email
  # WelcomeMailer.new("Alice", "alice@example.com")
  #   .to("alice@example.com")
  #   .subject("Welcome!")
  #   .deliver
  #
  # # Verify delivery
  # Amber::Mailer::MemoryAdapter.count.should eq 1
  # Amber::Mailer::MemoryAdapter.last.not_nil!.subject.should eq "Welcome!"
  # ```
  #
  # ## Thread Safety
  #
  # All access to the deliveries array is synchronized through a Mutex,
  # making this adapter safe for use in concurrent test environments.
  class MemoryAdapter < DeliveryAdapter
    @@list_of_deliveries = [] of Email
    @@mutex = Mutex.new

    # Delivers an email by storing it in the in-memory deliveries array.
    #
    # Always returns a successful delivery result.
    def deliver(email : Email) : DeliveryResult
      @@mutex.synchronize { @@list_of_deliveries << email }
      DeliveryResult.new(is_successful: true)
    end

    # Returns all emails that have been delivered through this adapter.
    def self.deliveries : Array(Email)
      @@mutex.synchronize { @@list_of_deliveries.dup }
    end

    # Clears all stored deliveries.
    #
    # Should be called in test setup or teardown to ensure a clean state.
    def self.clear : Nil
      @@mutex.synchronize { @@list_of_deliveries.clear }
    end

    # Returns the most recently delivered email, or nil if none have been delivered.
    def self.last : Email?
      @@mutex.synchronize { @@list_of_deliveries.last? }
    end

    # Returns the number of emails that have been delivered.
    def self.count : Int32
      @@mutex.synchronize { @@list_of_deliveries.size }
    end
  end
end
