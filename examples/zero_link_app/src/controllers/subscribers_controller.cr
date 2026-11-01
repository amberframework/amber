require "../schemas/create_subscriber_schema"

class SubscribersController < ApplicationController
  schema :create, CreateSubscriberSchema

  def create
    input = validated_as(CreateSubscriberSchema)
    # The schema marks email_address required, so a validated request
    # always has it; the named error documents that invariant.
    email_address = input.email_address
    raise Amber::Schema::InvalidSchemaError.new("email_address passed validation without a value") unless email_address

    subscriber = Subscriber.create!(email_address: email_address, first_name: input.first_name)
    payload = {
      "id"            => JSON::Any.new(subscriber.id),
      "email_address" => JSON::Any.new(subscriber.email_address),
    }
    respond_with(payload, status: 201)
  end
end
