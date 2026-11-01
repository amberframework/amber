# A newsletter subscriber, stored in PostgreSQL through Grant.
class Subscriber < Grant::Base
  connection primary
  table subscribers

  column id : Int64, primary: true
  column email_address : String
  column first_name : String?
  timestamps
end
