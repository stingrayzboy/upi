# frozen_string_literal: true

require 'bigdecimal'
require_relative 'encoding'

module Upi
  # A UPI URI read back apart, for inspecting a QR code you received rather than
  # one you built.
  #
  #   request = Upi::Request.parse('upi://pay?pa=merchant@upi&pn=Store&am=10.00&cu=INR')
  #   request.payee_address  # => "merchant@upi"
  #   request.amount         # => BigDecimal("10")
  #   request.warnings       # => ["tr is mandatory for merchant transactions..."]
  #
  # Parsing is deliberately forgiving where generation is strict: a QR in the
  # wild may well have been produced by a tool that got the encoding wrong, and
  # refusing to read it helps nobody. Problems surface through {#warnings} and
  # {#valid?} instead of exceptions, so you can tell a payer *why* their code
  # will not work.
  class Request
    PAY = 'pay'
    MANDATE = 'mandate'
    SCHEME = 'upi'

    # Tags carrying an amount, decoded to BigDecimal.
    AMOUNT_TAGS = %i[am mam fam].freeze

    ACCESSORS = {
      payee_address: :pa,
      payee_name: :pn,
      merchant_code: :mc,
      transaction_id: :tid,
      transaction_ref: :tr,
      note: :tn,
      currency: :cu,
      url: :url,
      initiation_mode: :mode,
      org_id: :orgid,
      signature: :sign
    }.freeze

    attr_reader :action, :tags, :uri

    ACCESSORS.each { |name, tag| define_method(name) { tags[tag] } }

    # @param uri [String] a `upi://pay?...` or `upi://mandate?...` string
    # @param plus_as_space [Boolean] decode `+` as a space. On by default: QR
    #   codes generated with form encoding are common, including ones this gem
    #   produced before 3.0.0.
    # @return [Request]
    # @raise [ParseError] if the string is not a UPI URI at all
    def self.parse(uri, plus_as_space: true)
      text = uri.to_s.strip
      raise ParseError, 'uri is empty' if text.empty?

      scheme, rest = text.split('://', 2)
      raise ParseError, "#{uri.to_s[0, 60].inspect} is not a upi:// URI" unless scheme&.downcase == SCHEME && rest

      action, query = rest.split('?', 2)
      new(action.to_s.downcase, parse_query(query, plus_as_space), text)
    end

    def self.parse_query(query, plus_as_space)
      query.to_s.split('#', 2).first.to_s.split('&').reject(&:empty?).each_with_object({}) do |pair, tags|
        key, value = pair.split('=', 2)
        decoded_key = Encoding.decode(key.to_s, plus_as_space: false).downcase
        next if decoded_key.empty?

        # First occurrence wins; a duplicated tag is reported as a warning.
        tags[decoded_key.to_sym] ||= Encoding.decode(value.to_s, plus_as_space: plus_as_space)
      end
    end
    private_class_method :parse_query

    def initialize(action, tags, uri)
      @action = action
      @tags = tags.freeze
      @uri = uri
    end

    def pay?
      action == PAY
    end

    def mandate?
      action == MANDATE
    end

    # @return [BigDecimal, nil]
    def amount
      decimal(:am)
    end

    # @return [BigDecimal, nil]
    def min_amount
      decimal(:mam)
    end

    def signed?
      !(tags[:sign].nil? || tags[:sign].empty?)
    end

    # A dynamic request carries an amount; a static one leaves it to the payer.
    def dynamic?
      !tags[:am].nil?
    end

    def merchant?
      !tags[:mc].nil?
    end

    # Everything wrong with this URI, in plain language, as an array of strings.
    # Empty means it looks payable.
    def warnings
      @warnings ||= collect_warnings.freeze
    end

    def valid?
      warnings.empty?
    end

    def to_h
      tags.dup
    end

    def inspect
      "#<#{self.class} #{action} #{tags.map { |k, v| "#{k}=#{v.inspect}" }.join(" ")}>"
    end

    private

    def decimal(tag)
      value = tags[tag]
      return nil if value.nil? || value.strip.empty?

      BigDecimal(value)
    rescue ArgumentError
      nil
    end

    def collect_warnings
      problems = []
      problems << 'pa (payee address) is missing' if blank?(:pa)
      problems << "pa #{tags[:pa].inspect} is not a valid UPI address" if invalid_vpa?
      problems << 'pn (payee name) is missing' if blank?(:pn)
      problems.concat(amount_warnings)
      problems.concat(field_warnings)
      problems
    end

    def amount_warnings
      AMOUNT_TAGS.flat_map { |tag| amount_warning(tag, tags[tag]) }.compact
    end

    def amount_warning(tag, raw)
      return [] if raw.nil?

      if raw.strip.empty? || !raw.match?(Validations::NUMERIC_PATTERN)
        ["#{tag}=#{raw.inspect} is not a valid amount"]
      elsif BigDecimal(raw).zero?
        ["#{tag}=0 is rejected by PSP apps; omit the tag to let the payer enter an amount"]
      elsif raw.include?('.') && raw.split('.').last.length > 2
        ["#{tag}=#{raw} has more than two decimal places"]
      else
        []
      end
    end

    # Each entry is a predicate and the message it earns.
    def field_rules
      [
        [unsupported_currency?, "cu=#{tags[:cu].inspect} is not supported; UPI only supports INR"],
        [bad_merchant_code?, "mc=#{tags[:mc].inspect} is not a four-digit merchant category code"],
        [missing_merchant_reference?,
         'tr is mandatory for merchant transactions carrying an amount, and must be unique per attempt'],
        [long_note?, "tn is #{tags[:tn].to_s.length} characters; the limit is #{Validations::MAX_LENGTHS[:tn]}"],
        [bad_url?, 'url must start with http:// or https://'],
        [suspicious_plus?, 'the URI contains a + where a space was probably meant; spaces must be %20']
      ]
    end

    def field_warnings
      field_rules.select(&:first).map(&:last)
    end

    def bad_merchant_code?
      merchant? && !tags[:mc].to_s.match?(Validations::MERCHANT_CODE_PATTERN)
    end

    def missing_merchant_reference?
      merchant? && dynamic? && blank?(:tr)
    end

    def long_note?
      !tags[:tn].nil? && tags[:tn].length > Validations::MAX_LENGTHS[:tn]
    end

    def bad_url?
      !tags[:url].nil? && !tags[:url].start_with?('http://', 'https://')
    end

    def blank?(tag)
      tags[tag].nil? || tags[tag].strip.empty?
    end

    def invalid_vpa?
      !blank?(:pa) && !tags[:pa].match?(Validations::VPA_PATTERN)
    end

    def unsupported_currency?
      !blank?(:cu) && tags[:cu].upcase != Validations::CURRENCY
    end

    # A literal `+` in the source means the generator used form encoding, which
    # shows up in the payer's app as "Test+User".
    def suspicious_plus?
      uri.split('?', 2).last.to_s.include?('+')
    end
  end
end
