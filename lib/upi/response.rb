# frozen_string_literal: true

require_relative 'encoding'

module Upi
  # The reply a PSP app hands back to the merchant app after a payment.
  #
  # Section 1.4 of the specification defines the shape:
  #
  #   txnId=abc...&responseCode=00&ApprovalRefNo=122321&Status=SUCCESS&txnRef=6655443322
  #
  #   response = Upi::Response.parse(params)
  #   response.success?        # => true
  #   response.transaction_ref # => "6655443322"
  #
  # The specification is emphatic that this is a hint, not proof: "As a standard
  # practice merchant app must check the final status with their server/PSP
  # server." Treat a SUCCESS here as a prompt to confirm server-side, never as
  # settlement. {#success?} tells you what the app claimed, nothing more.
  class Response
    SUCCESS = 'SUCCESS'
    FAILURE = 'FAILURE'
    SUBMITTED = 'SUBMITTED'

    # The response code for an approved transaction.
    APPROVED_CODE = '00'

    # Values PSP apps use to mean "no value", which must not survive as strings.
    NULL_VALUES = ['', 'null', 'NULL', 'nil', 'none'].freeze

    # Canonical keys from the specification, lower-cased for lookup. Apps vary
    # the casing in practice, so matching is case-insensitive.
    FIELDS = {
      'txnid' => :transaction_id,
      'responsecode' => :response_code,
      'approvalrefno' => :approval_ref_no,
      'status' => :status,
      'txnref' => :transaction_ref
    }.freeze

    attr_reader :transaction_id, :response_code, :approval_ref_no, :status, :transaction_ref, :raw

    # Parses a PSP response.
    #
    # @param input [String, Hash, nil] the raw query string, a full callback URL,
    #   or an already-parsed params hash
    # @param plus_as_space [Boolean] decode `+` as a space
    # @param params [Hash] the response fields, when passed as loose keywords
    # @return [Response]
    # @raise [ParseError] if nothing resembling a response is present
    #
    # Fields may be given positionally or as keywords, because Ruby 3 reads a
    # braceless hash literal as keywords and a caller should not have to care:
    #
    #   Response.parse(request.query_string)
    #   Response.parse(params)
    #   Response.parse(Status: 'SUCCESS', txnRef: 'A1')
    def self.parse(input = nil, plus_as_space: true, **params)
      source = input.nil? ? params : input
      raise ParseError, 'response is empty' if source.respond_to?(:empty?) && source.empty?

      new(extract(source, plus_as_space))
    end

    def self.extract(input, plus_as_space)
      return input.map { |key, value| [key.to_s.downcase, value.to_s] }.to_h if input.is_a?(Hash)

      text = input.to_s.strip
      raise ParseError, 'response is empty' if text.empty?

      pairs = split_pairs(query_of(text), plus_as_space)
      raise ParseError, "could not find any parameters in #{input.to_s[0, 60].inspect}" if pairs.empty?

      pairs.to_h
    end
    private_class_method :extract

    # Accept a full callback URL as readily as a bare query string.
    def self.query_of(text)
      query = text.include?('?') ? text.split('?', 2).last : text
      query.split('#', 2).first.to_s
    end
    private_class_method :query_of

    def self.split_pairs(query, plus_as_space)
      query.split('&').reject(&:empty?).map do |pair|
        key, value = pair.split('=', 2)
        [Encoding.decode(key.to_s, plus_as_space: plus_as_space).downcase,
         Encoding.decode(value.to_s, plus_as_space: plus_as_space)]
      end
    end
    private_class_method :split_pairs

    def initialize(params)
      @raw = params.freeze
      FIELDS.each { |key, attribute| instance_variable_set("@#{attribute}", nullify(params[key])) }
      @status = @status&.upcase
      return if FIELDS.keys.any? { |key| params.key?(key) }

      raise ParseError, "no UPI response fields present; got keys #{params.keys.inspect}"
    end

    # True when the PSP app reported the payment as approved.
    #
    # Confirm server-side before releasing goods; see the class documentation.
    def success?
      status == SUCCESS || (status.nil? && response_code == APPROVED_CODE)
    end

    def failure?
      status == FAILURE
    end

    # Still in flight. The app could not say either way, so the outcome must be
    # resolved against your PSP.
    def submitted?
      status == SUBMITTED
    end

    # True when the outcome is not yet decided and must be polled.
    def pending?
      submitted? || status.nil?
    end

    def to_h
      FIELDS.values.map { |attribute| [attribute, public_send(attribute)] }.to_h
    end

    def inspect
      "#<#{self.class} #{to_h.map { |k, v| "#{k}=#{v.inspect}" }.join(" ")}>"
    end

    private

    def nullify(value)
      return nil if value.nil?

      text = value.to_s.strip
      NULL_VALUES.include?(text) ? nil : text
    end
  end
end
