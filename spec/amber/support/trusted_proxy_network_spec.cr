require "../../spec_helper"

private def ip(address : String) : Socket::IPAddress
  Socket::IPAddress.new(address, 0)
end

module Amber::Support
  describe TrustedProxyNetwork do
    describe ".parse?" do
      it "accepts single IPv4 and IPv6 addresses" do
        TrustedProxyNetwork.parse?("127.0.0.1").should_not be_nil
        TrustedProxyNetwork.parse?("::1").should_not be_nil
      end

      it "accepts CIDR blocks" do
        TrustedProxyNetwork.parse?("10.0.0.0/8").should_not be_nil
        TrustedProxyNetwork.parse?("fd00::/8").should_not be_nil
        TrustedProxyNetwork.parse?("0.0.0.0/0").should_not be_nil
      end

      it "rejects text that is not an address or CIDR block" do
        TrustedProxyNetwork.parse?("localhost").should be_nil
        TrustedProxyNetwork.parse?("10.0.0.0/33").should be_nil
        TrustedProxyNetwork.parse?("::1/129").should be_nil
        TrustedProxyNetwork.parse?("10.0.0.0/x").should be_nil
        TrustedProxyNetwork.parse?("").should be_nil
      end
    end

    describe ".parse" do
      it "raises a ConfigurationError naming the bad entry" do
        expect_raises(Amber::Exceptions::ConfigurationError, /"proxy.internal"/) do
          TrustedProxyNetwork.parse("proxy.internal")
        end
      end
    end

    describe "#includes?" do
      it "matches addresses inside an IPv4 block" do
        network = TrustedProxyNetwork.parse("10.0.0.0/8")
        network.includes?(ip("10.244.3.7")).should be_true
        network.includes?(ip("11.0.0.1")).should be_false
      end

      it "matches a block with a prefix that is not a whole byte" do
        network = TrustedProxyNetwork.parse("172.16.0.0/12")
        network.includes?(ip("172.31.255.255")).should be_true
        network.includes?(ip("172.32.0.0")).should be_false
      end

      it "masks host bits written into the block" do
        TrustedProxyNetwork.parse("10.1.2.3/8").includes?(ip("10.200.0.1")).should be_true
      end

      it "matches a single address exactly" do
        network = TrustedProxyNetwork.parse("192.0.2.10")
        network.includes?(ip("192.0.2.10")).should be_true
        network.includes?(ip("192.0.2.11")).should be_false
      end

      it "matches an IPv4 peer seen through a dual-stack listener" do
        TrustedProxyNetwork.parse("127.0.0.0/8").includes?(ip("::ffff:127.0.0.1")).should be_true
      end

      it "matches IPv6 blocks" do
        network = TrustedProxyNetwork.parse("2001:db8::/32")
        network.includes?(ip("2001:db8:1::5")).should be_true
        network.includes?(ip("2001:db9::5")).should be_false
      end

      it "never matches a UNIX socket peer" do
        TrustedProxyNetwork.parse("0.0.0.0/0").includes?(Socket::UNIXAddress.new("/tmp/amber.sock")).should be_false
      end
    end
  end
end
