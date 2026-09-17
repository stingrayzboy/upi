# frozen_string_literal: true

require 'securerandom'
require_relative 'encoding'
require_relative 'rendering'
require_relative 'validations'

module Upi
  # Builds UPI payment URIs and QR codes that conform to the NPCI "UPI Linking
  # Specifications" (common URL specification for deep linking and proximity
  # integration, v1.6).
  #
  # The canonical example from that document is the shape this class targets:
  #
  #   upi://pay?pa=nadeem@npci&pn=nadeem%20chinna&mc=0000&tid=...&tr=...
  #            &tn=Pay%20to%20mystar%20store&am=10&mam=null&cu=INR&url=https://...
  #
  # Example usage:
  #
  #   generator = Upi::Generator.new(upi_id: 'test@upi', name: 'Test Name')
  #   svg = generator.generate_qr(100, 'Personal Payment', mode: :svg)
  #   png = generator.generate_qr(100, 'Personal Payment', mode: :png)
  #   uri = generator.upi_content(100, 'Personal Payment')
  #
  # Instances are immutable and safe to share between threads.
  #
  # @see https://www.npci.org.in/what-we-do/upi/product-overview
  class Generator
    include Validations
    include Rendering

    CURRENCY = Validations::CURRENCY

    # Transaction initiation modes from the specification's `mode` tag. The URI
    # is transport agnostic: the same string can be shown as a QR code, fired as
    # an Android intent, or pushed over NFC, BLE or UHF, and only this tag says
    # which route it took.
    MODE_DEFAULT = '00'
    MODE_QR = '01'
    MODE_SECURE_QR = '02'
    MODE_INTENT = '04'
    MODE_SECURE_INTENT = '05'
    MODE_NFC = '06'
    MODE_BLE = '07'
    MODE_UHF = '08'
    MODE_SEBI = '15'

    # Modes whose payload the specification expects to be signed.
    SECURE_MODES = [MODE_SECURE_QR, MODE_SECURE_INTENT].freeze

    # Emission order follows the example URIs in the specification. `sign` is
    # last because section 1.3 requires it: "sign shall be last tag".
    PARAM_ORDER = %i[pa pn mc tid tr tn am mam cu url mode orgid].freeze
    SIGNATURE_TAG = :sign

    attr_reader :params, :no_url_parse, :signer

    # @param upi_id [String] payee VPA, e.g. `'merchant@upi'`
    # @param name [String] payee name shown on the payer's confirmation screen
    # @param currency [String] ISO 4217 code; UPI only supports `'INR'`
    # @param merchant_code [String, nil] four-digit ISO 18245 merchant category
    #   code. Supplying it puts the generator in merchant (P2M) mode.
    # @param org_id [String, nil] six-digit `orgid`, required when signing
    # @param signer [Upi::Signer, nil] signs every URI this generator builds
    # @param no_url_parse [Boolean] `true` (default) percent-encodes values down
    #   to the RFC 3986 unreserved set; `false` leaves URL-safe punctuation
    #   readable. Both modes always escape the characters that would otherwise
    #   corrupt the query string.
    def initialize(upi_id:, name:, currency: CURRENCY, merchant_code: nil,
                   org_id: nil, signer: nil, no_url_parse: true)
      @upi_id = validate_vpa!(upi_id)
      @name = validate_text!(name, :pn, 'name')
      @currency = validate_currency!(currency)
      @merchant_code = validate_merchant_code!(merchant_code)
      @org_id = validate_org_id!(org_id)
      @signer = signer
      @no_url_parse = no_url_parse

      raise ValidationError, 'signing requires org_id (the six-digit orgid tag)' if @signer && @org_id.nil?

      @params = { pa: @upi_id, pn: @name, mc: @merchant_code, cu: @currency, orgid: @org_id }.compact.freeze
    end

    # Generates a unique transaction reference suitable for the `tr` field.
    #
    # A `tr` must be unique per payment attempt: PSPs reject a repeat of one
    # they have already seen, which is why a QR carrying a hard-coded reference
    # works once and then quietly stops.
    #
    # @param prefix [String] alphanumeric prefix to make references recognisable
    # @return [String]
    def self.generate_reference(prefix = 'UPI')
      raise ValidationError, "reference prefix #{prefix.inspect} must be alphanumeric" unless prefix.to_s.match?(Validations::REFERENCE_PATTERN)

      "#{prefix}#{Time.now.strftime("%Y%m%d%H%M%S")}#{SecureRandom.hex(4).upcase}"
    end

    # Builds the `upi://pay?...` URI.
    #
    # @param amount [Numeric, String, nil] payment amount. Omit it (or pass nil)
    #   to let the payer type an amount; UPI apps reject `am=0`.
    # @param note [String, nil] transaction note, max 50 characters
    # @param transaction_ref_id [String, nil] `tr`. Mandatory for merchant
    #   transactions carrying an amount, and must be unique per attempt.
    # @param transaction_id [String, nil] `tid`, PSP-generated when present
    # @param url [String, nil] `http`/`https` transaction detail URL
    # @param min_amount [Numeric, String, nil] `mam`. When given, the payer can
    #   edit the amount down to this floor.
    # @param initiation_mode [String, nil] `mode` tag, e.g. {MODE_QR}
    # @return [String]
    def upi_content(amount = nil, note = nil, transaction_ref_id: nil, transaction_id: nil,
                    url: nil, min_amount: nil, initiation_mode: nil)
      fields = build_fields(amount, note, transaction_ref_id, transaction_id, url,
                            min_amount, initiation_mode)
      content = serialize(fields)
      signer ? "#{content}&#{SIGNATURE_TAG}=#{encode(signer.sign(content))}" : content
    end

    # Renders the payment URI as a QR code.
    #
    # @param mode [Symbol] `:svg` (default) or `:png` output format
    # @param level [Symbol] QR error correction level, `:l`, `:m`, `:q` or `:h`
    # @param render_options [Hash] passed through to the rqrcode renderer,
    #   overriding the defaults (e.g. `module_px_size:`, `module_size:`)
    # @return [String] SVG markup, or raw PNG bytes
    # @see #upi_content for the payment parameters
    def generate_qr(amount = nil, note = nil, transaction_ref_id: nil, transaction_id: nil,
                    url: nil, min_amount: nil, initiation_mode: nil,
                    mode: :svg, level: :m, **render_options)
      check_render!(mode, render_options)
      content = upi_content(amount, note, transaction_ref_id: transaction_ref_id,
                                          transaction_id: transaction_id, url: url,
                                          min_amount: min_amount, initiation_mode: initiation_mode)

      render(content, mode, level, render_options)
    end

    private

    def serialize(fields)
      query = PARAM_ORDER.map do |key|
        next if key == :pa

        value = fields[key]
        "#{key}=#{encode(value, lenient: key == :url)}" unless value.nil?
      end.compact

      "upi://pay?pa=#{fields[:pa]}&#{query.join("&")}"
    end

    def build_fields(amount, note, transaction_ref_id, transaction_id, url, min_amount, initiation_mode)
      normalized_amount = normalize_amount(amount, 'amount')
      reference = validate_reference!(transaction_ref_id, :tr, 'transaction_ref_id')
      require_reference!(reference, normalized_amount)

      params.merge(
        tid: validate_reference!(transaction_id, :tid, 'transaction_id'),
        tr: reference,
        tn: presence(validate_text!(note, :tn, 'note')),
        am: normalized_amount,
        mam: normalize_min_amount(min_amount, normalized_amount),
        url: validate_url!(url),
        mode: validate_initiation_mode!(initiation_mode)
      )
    end

    # The specification marks `tr` mandatory for merchant transactions and for
    # dynamic (amount-bearing) URLs. Without it a PSP's risk engine sees an
    # amount-carrying merchant payload with nothing to reconcile against, and
    # rejects it behind a generic error.
    def require_reference!(reference, amount)
      return if reference || @merchant_code.nil? || amount.nil?

      raise ValidationError,
            'transaction_ref_id is mandatory for merchant transactions with an amount, ' \
            'and must be unique per payment attempt. ' \
            'Use Upi::Generator.generate_reference to build one.'
    end

    def normalize_min_amount(min_amount, amount)
      normalized = normalize_amount(min_amount, 'min_amount')
      return nil if normalized.nil?

      raise ValidationError, "min_amount #{normalized} cannot exceed amount #{amount}" if amount && BigDecimal(normalized) > BigDecimal(amount)

      normalized
    end

    def encode(value, lenient: false)
      Encoding.encode(value, lenient: lenient || !no_url_parse)
    end
  end
end
