# frozen_string_literal: true

require 'rqrcode'
require 'chunky_png'
require 'bigdecimal'
require 'securerandom'
require_relative 'upi/version'

module Upi
  # Base error class for the gem.
  class Error < StandardError; end

  # Raised when the supplied payment details cannot produce a spec-compliant UPI URI.
  #
  # Failing loudly at generation time is deliberate: an invalid UPI URI still
  # produces a perfectly scannable QR code, so the only symptom is a payment
  # that fails in the payer's app, long after the QR was handed out.
  class ValidationError < Error; end

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
    # Currently the only currency UPI supports.
    CURRENCY = 'INR'

    # Transaction initiation modes from the specification's `mode` tag.
    MODE_DEFAULT = '00'
    MODE_QR = '01'
    MODE_SECURE_QR = '02'
    MODE_INTENT = '04'

    # Field limits. `pa`/`pn` follow the NPCI field sizes; `tn` is the widely
    # enforced 50-character transaction note limit; `tr`/`tid` are kept inside
    # the shortest limit PSPs are known to apply.
    MAX_LENGTHS = { pa: 255, pn: 99, tn: 50, tr: 35, tid: 35 }.freeze

    # A virtual payment address: `local@psp`.
    VPA_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,}@[A-Za-z][A-Za-z0-9.-]{0,}\z/.freeze

    # Merchant category code, ISO 18245: exactly four digits.
    MERCHANT_CODE_PATTERN = /\A\d{4}\z/.freeze

    # Reference and transaction ids must be alphanumeric with no spaces.
    REFERENCE_PATTERN = /\A[A-Za-z0-9._-]+\z/.freeze

    NUMERIC_PATTERN = /\A\d+(\.\d+)?\z/.freeze

    # Largest amount we will emit. Per-transaction ceilings are set by the bank
    # and the merchant category, so this only catches obviously bad input.
    MAX_AMOUNT = BigDecimal('10000000000')

    # RFC 3986 unreserved set. Everything else is percent-encoded, which is what
    # makes a space `%20` rather than `+`.
    STRICT_UNSAFE = /[^A-Za-z0-9\-._~]/.freeze

    # Leaves characters that are legal inside a query value untouched, so a
    # redirect URL stays readable as `https://host/path` the way the NPCI
    # examples show it. `&`, `#`, `%`, `+` and space are still escaped, so a
    # value can never break out and forge another parameter.
    LENIENT_UNSAFE = %r{[^A-Za-z0-9\-._~:/?=@!$'()*,;]}.freeze

    # Emission order follows the example URIs in the specification.
    PARAM_ORDER = %i[pa pn mc tid tr tn am mam cu url mode].freeze

    # Renderer options accepted by rqrcode, used to reject a mistyped payment
    # keyword rather than let it fall through to the renderer and quietly drop a
    # field from the QR code.
    SVG_OPTIONS = %i[fill use_path offset color shape_rendering module_size standalone
                     viewbox svg_attributes].freeze
    PNG_OPTIONS = %i[bit_depth border_modules color_mode color file fill module_px_size
                     resize_exactly_to resize_gte_to size].freeze

    attr_reader :params, :no_url_parse

    # @param upi_id [String] payee VPA, e.g. `'merchant@upi'`
    # @param name [String] payee name shown on the payer's confirmation screen
    # @param currency [String] ISO 4217 code; UPI only supports `'INR'`
    # @param merchant_code [String, nil] four-digit ISO 18245 merchant category
    #   code. Supplying it puts the generator in merchant (P2M) mode.
    # @param no_url_parse [Boolean] `true` (default) percent-encodes values down
    #   to the RFC 3986 unreserved set; `false` leaves URL-safe punctuation
    #   readable. Both modes always escape the characters that would otherwise
    #   corrupt the query string.
    def initialize(upi_id:, name:, currency: CURRENCY, merchant_code: nil, no_url_parse: true)
      @upi_id = validate_vpa!(upi_id)
      @name = validate_text!(name, :pn, 'name')
      @currency = validate_currency!(currency)
      @merchant_code = validate_merchant_code!(merchant_code)
      @no_url_parse = no_url_parse
      @params = { pa: @upi_id, pn: @name, mc: @merchant_code, cu: @currency }.compact.freeze
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
      raise ValidationError, "reference prefix #{prefix.inspect} must be alphanumeric" unless prefix.to_s.match?(REFERENCE_PATTERN)

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
      query = PARAM_ORDER.map do |key|
        next if key == :pa

        value = fields[key]
        "#{key}=#{encode(value, lenient: key == :url)}" unless value.nil?
      end.compact

      "upi://pay?pa=#{fields[:pa]}&#{query.join("&")}"
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
      raise ArgumentError, "Unsupported mode: #{mode}. Use :svg or :png." unless %i[svg png].include?(mode)

      validate_render_options!(render_options, mode)
      content = upi_content(amount, note, transaction_ref_id: transaction_ref_id,
                                          transaction_id: transaction_id, url: url,
                                          min_amount: min_amount, initiation_mode: initiation_mode)
      qrcode = RQRCode::QRCode.new(content, level: level)

      mode == :svg ? render_svg(qrcode, render_options) : render_png(qrcode, render_options)
    end

    private

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

    def validate_vpa!(upi_id)
      value = upi_id.to_s.strip
      raise ValidationError, 'upi_id is required' if value.empty?

      raise ValidationError, "upi_id must be at most #{MAX_LENGTHS[:pa]} characters" if value.length > MAX_LENGTHS[:pa]
      raise ValidationError, "upi_id #{upi_id.inspect} is not a valid UPI address (expected 'name@psp')" unless value.match?(VPA_PATTERN)

      value
    end

    def validate_text!(text, key, label)
      return nil if text.nil?

      value = text.to_s.tr("\r\n\t", ' ').strip
      if value.length > MAX_LENGTHS[key]
        raise ValidationError,
              "#{label} must be at most #{MAX_LENGTHS[key]} characters, got #{value.length}"
      end
      raise ValidationError, "#{label} is required" if key == :pn && value.empty?

      value
    end

    def validate_currency!(currency)
      value = currency.to_s.strip.upcase
      raise ValidationError, "currency #{currency.inspect} is not supported; UPI only supports 'INR'" unless value == CURRENCY

      value
    end

    def validate_merchant_code!(merchant_code)
      return nil if merchant_code.nil?

      value = merchant_code.to_s.strip
      unless value.match?(MERCHANT_CODE_PATTERN)
        raise ValidationError,
              "merchant_code #{merchant_code.inspect} must be a four-digit ISO 18245 category code"
      end

      value
    end

    def validate_reference!(reference, key, label)
      return nil if reference.nil?

      value = reference.to_s.strip
      return nil if value.empty?

      raise ValidationError, "#{label} must be at most #{MAX_LENGTHS[key]} characters, got #{value.length}" if value.length > MAX_LENGTHS[key]
      raise ValidationError, "#{label} #{reference.inspect} must be alphanumeric with no spaces" unless value.match?(REFERENCE_PATTERN)

      value
    end

    def validate_url!(url)
      return nil if url.nil?

      value = url.to_s.strip
      return nil if value.empty?
      raise ValidationError, "url #{url.inspect} must start with http:// or https://" unless value.start_with?('http://', 'https://')

      value
    end

    def validate_initiation_mode!(initiation_mode)
      return nil if initiation_mode.nil?

      value = initiation_mode.to_s
      raise ValidationError, "initiation_mode #{initiation_mode.inspect} must be two digits" unless value.match?(/\A\d{2}\z/)

      value
    end

    def normalize_min_amount(min_amount, amount)
      normalized = normalize_amount(min_amount, 'min_amount')
      return nil if normalized.nil?

      raise ValidationError, "min_amount #{normalized} cannot exceed amount #{amount}" if amount && BigDecimal(normalized) > BigDecimal(amount)

      normalized
    end

    # UPI amounts are decimal with at most two places. Emitting anything else --
    # `am=0`, `am=1499.5`, or the `0.30000000000000004` a float sum produces --
    # is rejected by PSP apps, so normalize here and reject what cannot be
    # represented rather than silently rounding someone's money.
    def normalize_amount(amount, label)
      return nil if amount.nil?
      return nil if amount.is_a?(String) && amount.strip.empty?

      decimal = to_decimal(amount, label)
      raise ValidationError, "#{label} must be greater than zero, got #{amount.inspect}" unless decimal.positive?
      raise ValidationError, "#{label} #{amount.inspect} is too large" if decimal > MAX_AMOUNT

      if decimal != decimal.round(2)
        raise ValidationError,
              "#{label} #{amount.inspect} has more than two decimal places; " \
              'UPI amounts allow at most two. Round it before passing it in.'
      end

      whole, fraction = decimal.to_s('F').split('.')
      "#{whole}.#{fraction.to_s.ljust(2, "0")[0, 2]}"
    end

    def to_decimal(amount, label)
      case amount
      when BigDecimal then amount
      when Integer then BigDecimal(amount)
      # 15 significant digits discards IEEE representation noise (0.1 + 0.2)
      # while preserving precision the caller actually meant.
      when Float, Rational then BigDecimal(amount, 15)
      when String
        value = amount.strip
        raise ValidationError, "#{label} #{amount.inspect} is not a valid number" unless value.match?(NUMERIC_PATTERN)

        BigDecimal(value)
      else
        raise ValidationError, "#{label} must be Numeric or String, got #{amount.class}"
      end
    end

    def presence(value)
      value unless value.nil? || value.empty?
    end

    def encode(value, lenient: false)
      pattern = lenient || !no_url_parse ? LENIENT_UNSAFE : STRICT_UNSAFE
      value.to_s.gsub(pattern) { |char| char.bytes.map { |byte| format('%%%02X', byte) }.join }
    end

    def validate_render_options!(options, mode)
      allowed = mode == :svg ? SVG_OPTIONS : PNG_OPTIONS
      unknown = options.keys - allowed
      return if unknown.empty?

      raise ArgumentError,
            "unknown keyword#{"s" if unknown.size > 1}: #{unknown.map(&:inspect).join(", ")}. " \
            "Payment details go to #upi_content's parameters; #{mode} renderer options are: " \
            "#{allowed.join(", ")}."
    end

    def render_svg(qrcode, options)
      qrcode.as_svg({ color: '000', shape_rendering: 'crispEdges', module_size: 11 }.merge(options))
    end

    # Sizing is driven by module size rather than a fixed canvas: a longer
    # payload needs more modules, and pinning the canvas shrinks each module
    # until scanners start to struggle.
    def render_png(qrcode, options)
      defaults = {
        bit_depth: 1,
        border_modules: 4,
        color_mode: ChunkyPNG::COLOR_GRAYSCALE,
        color: 'black',
        file: nil,
        fill: 'white',
        module_px_size: 8,
        resize_exactly_to: false,
        resize_gte_to: false
      }
      qrcode.as_png(**defaults.merge(options)).to_s
    end
  end
end
