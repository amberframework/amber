# The contract for POST /api/subscribers. The same schema accepts a JSON
# object or, through the Mica parser registered in
# config/initializers/request_body_parsers.cr, the equivalent XML document.
class CreateSubscriberSchema < Amber::Schema::Definition
  content_type "application/json", "application/xml", "text/xml"
  additional_properties false

  field :email_address, String, required: true, format: "email"
  field :first_name, String, max_length: 80
end
