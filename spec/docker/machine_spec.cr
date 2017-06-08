require "../spec_helper"

module Amber::CMD::Docker::Machine
  describe Command do
    it "define machine for DigitalOcean" do
      command = Command.new("digitalocean", "spec/seeds/config.yml")

      command.build.should eq "--driver digitalocean --digitalocean-access-token=accesstokenhere --digitalocean-image=ubuntu-16-04-x64 --digitalocean-private-networking=true --digitalocean-size=2gb"
    end

    it "define machine for Amazon Web Services" do
      command = Command.new("amazonec2", "spec/seeds/config.yml")

      command.build.should eq "--driver amazonec2 --amazonec2-ami=ami-5f709f34 --amazonec2-region=us-east-1 --amazonec2-zone=a"
    end
  end
end
