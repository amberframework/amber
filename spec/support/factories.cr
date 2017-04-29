require "../../src/amber/*"
require "../../src/amber/**"

class HelloController < Amber::Controller::Base
  def index; end

  def world
    "Hello World!"
  end
end

struct UserSocket < Amber::WebSockets::ClientSocket
  channel "user_room/*", UserChannel
end

class UserChannel < Amber::WebSockets::Channel
  def joined;end
end