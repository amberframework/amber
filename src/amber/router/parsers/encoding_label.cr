module Amber::Router::Parsers
  # Resolves the `charset` a request declares to an encoding Amber decodes.
  #
  # Only the labels of the WHATWG Encoding Standard resolve
  # (https://encoding.spec.whatwg.org/#names-and-labels), so a client cannot
  # pick a converter out of the platform's iconv by name. Two encodings of
  # that table have no decoder here and their labels do not resolve:
  # `replacement` (the standard's own refusal of `ISO-2022-KR`, `ISO-2022-CN`,
  # `ISO-2022-CN-EXT` and `HZ-GB-2312`) and `x-user-defined`.
  module EncodingLabel
    # An encoding of the standard: its *name* there and the *decoder_name*
    # handed to `IO#set_encoding`. The decoder is the one whose table matches
    # the standard's, which is why `Shift_JIS` decodes as `CP932` and `GBK`
    # as `GB18030`.
    record Encoding, name : String, decoder_name : String do
      def utf8? : Bool
        name == "UTF-8"
      end
    end

    # Longer than any label, with room for surrounding whitespace.
    MAX_LABEL_BYTES = 64

    private LIST_OF_ENCODINGS = [
      {"UTF-8", "UTF-8", %w(unicode-1-1-utf-8 unicode11utf8 unicode20utf8 utf-8 utf8 x-unicode20utf8)},
      {"IBM866", "CP866", %w(866 cp866 csibm866 ibm866)},
      {"ISO-8859-2", "ISO-8859-2", %w(csisolatin2 iso-8859-2 iso-ir-101 iso8859-2 iso88592 iso_8859-2 iso_8859-2:1987 l2 latin2)},
      {"ISO-8859-3", "ISO-8859-3", %w(csisolatin3 iso-8859-3 iso-ir-109 iso8859-3 iso88593 iso_8859-3 iso_8859-3:1988 l3 latin3)},
      {"ISO-8859-4", "ISO-8859-4", %w(csisolatin4 iso-8859-4 iso-ir-110 iso8859-4 iso88594 iso_8859-4 iso_8859-4:1988 l4 latin4)},
      {"ISO-8859-5", "ISO-8859-5", %w(csisolatincyrillic cyrillic iso-8859-5 iso-ir-144 iso8859-5 iso88595 iso_8859-5 iso_8859-5:1988)},
      {"ISO-8859-6", "ISO-8859-6", %w(arabic asmo-708 csiso88596e csiso88596i csisolatinarabic ecma-114 iso-8859-6 iso-8859-6-e iso-8859-6-i iso-ir-127 iso8859-6 iso88596 iso_8859-6 iso_8859-6:1987)},
      {"ISO-8859-7", "ISO-8859-7", %w(csisolatingreek ecma-118 elot_928 greek greek8 iso-8859-7 iso-ir-126 iso8859-7 iso88597 iso_8859-7 iso_8859-7:1987 sun_eu_greek)},
      {"ISO-8859-8", "ISO-8859-8", %w(csiso88598e csisolatinhebrew hebrew iso-8859-8 iso-8859-8-e iso-ir-138 iso8859-8 iso88598 iso_8859-8 iso_8859-8:1988 visual)},
      {"ISO-8859-8-I", "ISO-8859-8", %w(csiso88598i iso-8859-8-i logical)},
      {"ISO-8859-10", "ISO-8859-10", %w(csisolatin6 iso-8859-10 iso-ir-157 iso8859-10 iso885910 l6 latin6)},
      {"ISO-8859-13", "ISO-8859-13", %w(iso-8859-13 iso8859-13 iso885913)},
      {"ISO-8859-14", "ISO-8859-14", %w(iso-8859-14 iso8859-14 iso885914)},
      {"ISO-8859-15", "ISO-8859-15", %w(csisolatin9 iso-8859-15 iso8859-15 iso885915 iso_8859-15 l9)},
      {"ISO-8859-16", "ISO-8859-16", %w(iso-8859-16)},
      {"KOI8-R", "KOI8-R", %w(cskoi8r koi koi8 koi8-r koi8_r)},
      {"KOI8-U", "KOI8-U", %w(koi8-ru koi8-u)},
      {"macintosh", "MACINTOSH", %w(csmacintosh mac macintosh x-mac-roman)},
      {"windows-874", "CP874", %w(dos-874 iso-8859-11 iso8859-11 iso885911 tis-620 windows-874)},
      {"windows-1250", "CP1250", %w(cp1250 windows-1250 x-cp1250)},
      {"windows-1251", "CP1251", %w(cp1251 windows-1251 x-cp1251)},
      {"windows-1252", "CP1252", %w(ansi_x3.4-1968 ascii cp1252 cp819 csisolatin1 ibm819 iso-8859-1 iso-ir-100 iso8859-1 iso88591 iso_8859-1 iso_8859-1:1987 l1 latin1 us-ascii windows-1252 x-cp1252)},
      {"windows-1253", "CP1253", %w(cp1253 windows-1253 x-cp1253)},
      {"windows-1254", "CP1254", %w(cp1254 csisolatin5 iso-8859-9 iso-ir-148 iso8859-9 iso88599 iso_8859-9 iso_8859-9:1989 l5 latin5 windows-1254 x-cp1254)},
      {"windows-1255", "CP1255", %w(cp1255 windows-1255 x-cp1255)},
      {"windows-1256", "CP1256", %w(cp1256 windows-1256 x-cp1256)},
      {"windows-1257", "CP1257", %w(cp1257 windows-1257 x-cp1257)},
      {"windows-1258", "CP1258", %w(cp1258 windows-1258 x-cp1258)},
      {"x-mac-cyrillic", "MACCYRILLIC", %w(x-mac-cyrillic x-mac-ukrainian)},
      {"GBK", "GB18030", %w(chinese csgb2312 csiso58gb231280 gb2312 gb_2312 gb_2312-80 gbk iso-ir-58 x-gbk)},
      {"gb18030", "GB18030", %w(gb18030)},
      {"Big5", "BIG5-HKSCS", %w(big5 big5-hkscs cn-big5 csbig5 x-x-big5)},
      {"EUC-JP", "EUC-JP", %w(cseucpkdfmtjapanese euc-jp x-euc-jp)},
      {"ISO-2022-JP", "ISO-2022-JP", %w(csiso2022jp iso-2022-jp)},
      {"Shift_JIS", "CP932", %w(csshiftjis ms932 ms_kanji shift-jis shift_jis sjis windows-31j x-sjis)},
      {"EUC-KR", "CP949", %w(cseuckr csksc56011987 euc-kr iso-ir-149 korean ks_c_5601-1987 ks_c_5601-1989 ksc5601 ksc_5601 windows-949)},
      {"UTF-16BE", "UTF-16BE", %w(unicodefffe utf-16be)},
      {"UTF-16LE", "UTF-16LE", %w(csunicode iso-10646-ucs-2 ucs-2 unicode unicodefeff utf-16 utf-16le)},
    ]

    private ENCODING_BY_LABEL = LIST_OF_ENCODINGS.each_with_object({} of String => Encoding) do |(name, decoder_name, list_of_labels), encoding_by_label|
      encoding = Encoding.new(name, decoder_name)
      list_of_labels.each { |label| encoding_by_label[label] = encoding }
    end

    # The encoding *label* names, or nil when it is not a label of the
    # standard. As the standard has it, ASCII whitespace around the label and
    # its letter case are ignored.
    def self.resolve?(label : String) : Encoding?
      return if label.bytesize > MAX_LABEL_BYTES
      ENCODING_BY_LABEL[label.strip(" \t\n\f\r").downcase]?
    end
  end
end
