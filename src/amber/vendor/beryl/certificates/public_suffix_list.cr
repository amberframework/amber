module Amber::Beryl::Certificates
  # The Public Suffix List (https://publicsuffix.org), used to refuse a
  # wildcard that covers a whole public suffix such as `*.co.uk` or
  # `*.s3.amazonaws.com` (CA/Browser Forum baseline requirements §3.2.2.6).
  #
  # The list is `data/public_suffix_list.dat`, pinned by sha256 (see
  # `SHA256`) and updated with `scripts/update_certificate_data.rb`. It is
  # published under the Mozilla Public License 2.0, whose notice heads the
  # file. Only ASCII rules (A-labels) are used; the list's rules in Unicode
  # form are converted by IDNA in browsers and never match the ASCII names a
  # certificate holds, except through their `xn--` form, which the list
  # does not carry, so those rules are left out.
  module PublicSuffixList
    # The sha256 of `data/public_suffix_list.dat`, checked by a spec.
    SHA256 = "00a0af2ed2379634523b9ca80de3469d1466893915c252a91264e248c92d69d8"
    # The upstream commit the file was taken at.
    COMMIT = "87a2c1b8de5886a133ff4da21b2aa6fec88d8739"

    TEXT = {{ read_file("#{__DIR__}/data/public_suffix_list.dat") }}

    # The three kinds of rule.
    record Rules, list_of_names : Set(String), list_of_wildcard_parents : Set(String), list_of_exceptions : Set(String)

    class_getter rules : Rules do
      names = Set(String).new
      wildcard_parents = Set(String).new
      exceptions = Set(String).new
      TEXT.each_line do |line|
        rule = line.strip
        next if rule.empty? || rule.starts_with?("//") || !rule.ascii_only?

        rule = rule.downcase
        if rule.starts_with?('!')
          exceptions << rule[1..]
        elsif rule.starts_with?("*.")
          wildcard_parents << rule[2..]
        else
          names << rule
        end
      end
      Rules.new(names, wildcard_parents, exceptions)
    end

    # Returns whether *name* (lowercase, without a final dot) is a public
    # suffix: a name listed, a name under a listed wildcard and not listed
    # as an exception, or a single label (the list's implicit `*` rule).
    def self.public_suffix?(name : String) : Bool
      return false if rules.list_of_exceptions.includes?(name)
      return true if rules.list_of_names.includes?(name)

      first_dot = name.index('.')
      return true unless first_dot
      rules.list_of_wildcard_parents.includes?(name[first_dot + 1..])
    end
  end
end
