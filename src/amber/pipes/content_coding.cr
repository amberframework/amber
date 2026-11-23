module Amber
  module Pipe
    # Content-coding negotiation from a request's `Accept-Encoding` field
    # (RFC 9110, section 12.5.3), shared by `Compression` and `Static`.
    #
    # Each coding's quality comes from its own entry, or from `*` when it
    # has none (`gzip` also matches `x-gzip`). A coding with no entry and no
    # `*` is not acceptable, except `identity`, which is acceptable unless
    # an entry or `*` gives it quality 0. A quality that is not a number
    # counts as 0.
    #
    # ```
    # headers = HTTP::Headers{"Accept-Encoding" => "gzip;q=0.8, br"}
    # Amber::Pipe::ContentCoding.choose(headers, ["br", "gzip"])                                            # => "br"
    # Amber::Pipe::ContentCoding.quality(headers, "gzip")                                                   # => 0.8
    # Amber::Pipe::ContentCoding.choose(HTTP::Headers{"Accept-Encoding" => "br;q=0, gzip"}, ["br", "gzip"]) # => "gzip"
    # ```
    module ContentCoding
      # Returns the quality the request gives *coding* (lowercase), 0.0 to
      # 1.0. Without an `Accept-Encoding` field every coding is acceptable
      # (quality 1.0), as RFC 9110 says; callers that compress should treat
      # a missing field as `identity` only, which `choose` does.
      def self.quality(headers : HTTP::Headers, coding : String) : Float64
        list_of_values = headers.get?("Accept-Encoding")
        return 1.0 unless list_of_values

        # Specificity is 1 for the coding's own entry and 0 for `*`; the
        # first entry of the highest specificity decides.
        best_specificity = -1
        best_quality = coding == "identity" ? 1.0 : 0.0
        list_of_values.each do |value|
          value.split(',') do |entry|
            name, _, parameters = entry.partition(';')
            name = name.strip(" \t").downcase
            specificity = if name == coding || (coding == "gzip" && name == "x-gzip")
                            1
                          elsif name == "*"
                            0
                          else
                            -1
                          end
            next unless specificity > best_specificity

            best_specificity = specificity
            best_quality = quality_parameter(parameters)
          end
        end
        best_quality
      end

      # Returns the coding of *list_of_offered* (in the server's order of
      # preference) with the highest quality above 0, the earlier one on a
      # tie; nil when none is acceptable or the request has no
      # `Accept-Encoding` field.
      def self.choose(headers : HTTP::Headers, list_of_offered : Array(String)) : String?
        return nil unless headers.has_key?("Accept-Encoding")

        chosen = nil
        chosen_quality = 0.0
        list_of_offered.each do |coding|
          coding_quality = quality(headers, coding)
          if coding_quality > chosen_quality
            chosen = coding
            chosen_quality = coding_quality
          end
        end
        chosen
      end

      # Reads the `q` parameter from the parameters after a coding, as in
      # `q=0.5` or `level=1; q=0`. A missing `q` is 1; a `q` that is not a
      # number is 0.
      private def self.quality_parameter(parameters : String) : Float64
        quality = 1.0
        parameters.split(';') do |parameter|
          name, _, value = parameter.partition('=')
          next unless name.strip(" \t").downcase == "q"

          parsed_quality = value.strip(" \t").to_f?
          quality = parsed_quality ? parsed_quality.clamp(0.0, 1.0) : 0.0
        end
        quality
      end
    end
  end
end
