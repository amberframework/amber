require "./certificate"
require "./service_identity"

module Amber::Beryl::Certificates
  # Applies one CA's name constraints (RFC 5280 §4.2.1.10) to the names of
  # a certificate below it.
  #
  # - dNSName: a constraint `example.com` covers that name and every name
  #   ending in `.example.com`; an empty constraint covers every name. A
  #   constraint with a wildcard or a leading period is malformed.
  #   A presented wildcard `*.base` is inside a permitted subtree only when
  #   all of it is (base within the subtree), and hits an excluded subtree
  #   when any name it could match would (base within the subtree, or the
  #   subtree within `*.base`), which closes CVE-2025-61727.
  # - iPAddress: address and mask of 8 or 16 bytes, the mask contiguous.
  # - rfc822Name: a mailbox (`user@host`, the local part compared exactly),
  #   a host (`host`, every mailbox there) or a domain (`.domain`, every
  #   mailbox at a host below it); an asterisk is a literal character.
  # - uniformResourceIdentifier: the URI's host against `host` or `.domain`.
  # - directoryName: the subject name, and directory names in the subject
  #   alternative names, must begin with the constraint's relative names.
  #
  # Email addresses in the subject's emailAddress attributes count as
  # rfc822Name. A constraint of a kind Beryl does not process (otherName,
  # x400Address, ediPartyName, registeredID) refuses any certificate that
  # carries a name of that kind, and is harmless otherwise.
  #
  # Every comparison is counted against a budget shared by the whole
  # validation, so a certificate with thousands of names under thousands of
  # constraints is refused instead of taking quadratic time.
  class NameConstraintCheck
    # Raised inside the check when the budget runs out.
    class BudgetExhausted < Exception
    end

    getter comparison_count : Int64 = 0

    def initialize(@largest_comparison_count : Int64)
    end

    # Returns why *constraints* are malformed, or `nil` when they are
    # well formed.
    def self.malformed_reason(constraints : NameConstraints) : String?
      permitted = constraints.list_of_permitted_subtrees
      excluded = constraints.list_of_excluded_subtrees
      return "name constraints with neither permitted nor excluded subtrees" if permitted.nil? && excluded.nil?
      return "name constraints with an empty permittedSubtrees" if permitted && permitted.empty?
      return "name constraints with an empty excludedSubtrees" if excluded && excluded.empty?
      return "a name constraint subtree with minimum or maximum (RFC 5280 §4.2.1.10)" if constraints.has_subtree_with_bounds

      {permitted, excluded}.each do |list|
        next unless list
        list.each do |constraint|
          if reason = malformed_constraint_reason(constraint)
            return reason
          end
        end
      end
      nil
    end

    private def self.malformed_constraint_reason(constraint : GeneralName) : String?
      case constraint.kind
      when .domain_name?
        text = constraint.text
        return nil if text.empty?
        return "a dNSName constraint #{text.inspect} is not a host name" unless ServiceIdentity.valid_host_name?(text)
      when .internet_protocol_address?
        value = constraint.value
        return "an iPAddress constraint of #{value.size} bytes" unless value.size == 8 || value.size == 32
        return "an iPAddress constraint whose mask is not contiguous" unless contiguous_mask?(value[value.size // 2, value.size // 2])
      when .electronic_mail_address?
        return "an rfc822Name constraint #{constraint.text.inspect} is malformed" unless valid_mail_constraint?(constraint.text)
      when .uniform_resource_identifier?
        text = constraint.text
        host = text.starts_with?('.') ? text[1..] : text
        return "a URI constraint #{text.inspect} is not a host or domain" unless ServiceIdentity.valid_host_name?(host)
      end
      nil
    end

    private def self.contiguous_mask?(mask : Bytes) : Bool
      seen_zero = false
      mask.each do |byte|
        8.times do |bit|
          if (byte >> (7 - bit)) & 1 == 1
            return false if seen_zero
          else
            seen_zero = true
          end
        end
      end
      true
    end

    private def self.valid_mail_constraint?(text : String) : Bool
      return false if text.empty?

      at_count = text.count('@')
      return false if at_count > 1
      if at_count == 1
        local, host = text.split('@', 2)
        !local.empty? && ServiceIdentity.valid_host_name?(host)
      else
        ServiceIdentity.valid_host_name?(text.starts_with?('.') ? text[1..] : text)
      end
    end

    # Returns why *certificate*'s names break *constraints*, or `nil` when
    # every name is allowed. *constraints* must be well formed.
    def violation(constraints : NameConstraints, certificate : Certificate) : String?
      list_of_names = names_of(certificate)
      permitted = constraints.list_of_permitted_subtrees || [] of GeneralName
      excluded = constraints.list_of_excluded_subtrees || [] of GeneralName

      list_of_names.each do |name|
        kind = name.kind
        list_of_excluded = excluded.select { |constraint| constraint.kind == kind }
        list_of_permitted = permitted.select { |constraint| constraint.kind == kind }
        next if list_of_excluded.empty? && list_of_permitted.empty?

        case kind
        when .domain_name?, .internet_protocol_address?, .electronic_mail_address?, .uniform_resource_identifier?, .directory_name?
          unless well_formed_name?(name)
            return "the #{kind} #{describe(name)} is malformed and cannot be checked against the name constraints"
          end
          list_of_excluded.each do |constraint|
            return "the #{kind} #{describe(name)} is excluded by the name constraints" if hits_excluded?(name, constraint)
          end
          unless list_of_permitted.empty? || list_of_permitted.any? { |constraint| within_permitted?(name, constraint) }
            return "the #{kind} #{describe(name)} is outside the permitted name constraints"
          end
        else
          return "the certificate has a #{kind} name, a kind of name constraint Beryl does not process"
        end
      end
      nil
    end

    private def names_of(certificate : Certificate) : Array(GeneralName)
      list_of_names = [] of GeneralName
      subject = certificate.subject
      unless subject.empty?
        list_of_names << GeneralName.new(GeneralName::Kind::DirectoryName, subject.encoded, subject)
        subject.list_of_values(ObjectIdentifiers::EMAIL_ADDRESS).each do |attribute|
          if value = attribute.string_value
            list_of_names << GeneralName.new(GeneralName::Kind::ElectronicMailAddress, value)
          end
        end
      end
      if list = certificate.list_of_subject_alternative_names
        list_of_names.concat(list)
      end
      list_of_names
    end

    private def describe(name : GeneralName) : String
      case name.kind
      when .internet_protocol_address? then ServiceIdentity.format_ip_address(name.value)
      when .directory_name?            then name.directory_name.to_s
      else                                  name.text.inspect
      end
    end

    private def well_formed_name?(name : GeneralName) : Bool
      case name.kind
      when .domain_name?
        text = name.text
        ServiceIdentity.valid_host_name?(text.starts_with?("*.") ? text[2..] : text)
      when .internet_protocol_address?
        name.value.size == 4 || name.value.size == 16
      when .electronic_mail_address?
        mailbox = split_mailbox(name.text)
        !mailbox.nil?
      when .uniform_resource_identifier?
        !uri_host(name.text).nil?
      else
        true
      end
    end

    private def count_comparison : Nil
      @comparison_count += 1
      raise BudgetExhausted.new if @comparison_count > @largest_comparison_count
    end

    private def within_permitted?(name : GeneralName, constraint : GeneralName) : Bool
      count_comparison
      case name.kind
      when .domain_name?
        text = name.text.downcase
        base = constraint.text.downcase
        text.starts_with?("*.") ? dns_within?(text[2..], base) : dns_within?(text, base)
      else
        matches?(name, constraint)
      end
    end

    private def hits_excluded?(name : GeneralName, constraint : GeneralName) : Bool
      count_comparison
      case name.kind
      when .domain_name?
        text = name.text.downcase
        base = constraint.text.downcase
        if text.starts_with?("*.")
          wildcard_base = text[2..]
          dns_within?(wildcard_base, base) || base.ends_with?(".#{wildcard_base}")
        else
          dns_within?(text, base)
        end
      else
        matches?(name, constraint)
      end
    end

    private def matches?(name : GeneralName, constraint : GeneralName) : Bool
      case name.kind
      when .internet_protocol_address?
        address = name.value
        half = constraint.value.size // 2
        return false unless address.size == half

        address.each_with_index.all? do |byte, index|
          mask = constraint.value[half + index]
          byte & mask == constraint.value[index] & mask
        end
      when .electronic_mail_address?
        mail_within?(name.text, constraint.text)
      when .uniform_resource_identifier?
        host = uri_host(name.text)
        return false unless host
        constraint_text = constraint.text.downcase
        if constraint_text.starts_with?('.')
          host.ends_with?(constraint_text)
        else
          host == constraint_text
        end
      when .directory_name?
        prefix = constraint.directory_name
        directory = name.directory_name
        !prefix.nil? && !directory.nil? && directory.starts_with?(prefix)
      else
        false
      end
    end

    private def dns_within?(name : String, base : String) : Bool
      base.empty? || name == base || name.ends_with?(".#{base}")
    end

    private def split_mailbox(text : String) : {String, String}?
      return nil unless text.count('@') == 1

      local, host = text.split('@', 2)
      return nil if local.empty? || !ServiceIdentity.valid_host_name?(host)
      {local, host.downcase}
    end

    private def mail_within?(address : String, constraint : String) : Bool
      mailbox = split_mailbox(address)
      return false unless mailbox
      local, host = mailbox

      if constraint.includes?('@')
        constraint_local, constraint_host = constraint.split('@', 2)
        local == constraint_local && host == constraint_host.downcase
      elsif constraint.starts_with?('.')
        host.ends_with?(constraint.downcase)
      else
        host == constraint.downcase
      end
    end

    # The host of a URI with an authority (`scheme://[userinfo@]host[:port]...`),
    # lowercase, or `nil` when the URI has none or the host is not a name.
    private def uri_host(text : String) : String?
      scheme_end = text.index("://")
      return nil unless scheme_end && scheme_end > 0

      authority_start = scheme_end + 3
      authority_end = (authority_start...text.size).find { |index| {'/', '?', '#'}.includes?(text[index]) } || text.size
      authority = text[authority_start, authority_end - authority_start]
      at = authority.rindex('@')
      host_and_port = at ? authority[at + 1..] : authority
      return nil if host_and_port.starts_with?('[')
      host = host_and_port.split(':', 2).first.downcase
      ServiceIdentity.valid_host_name?(host) ? host : nil
    end
  end
end
