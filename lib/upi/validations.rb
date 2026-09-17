# frozen_string_literal: true

require 'bigdecimal'

module Upi
  # Field rules shared by the payment and mandate builders.
  #
  # Every rule here exists because violating it produces a QR code that scans
  # perfectly and then fails in the payer's app.
  module Validations
    CURRENCY = 'INR'

    # `pa`/`pn` follow the NPCI field sizes; `tn` is the widely enforced
    # 50-character note limit; `tr`/`tid` sit inside the shortest limit PSPs are
    # known to apply; `mn` is the mandate name.
    MAX_LENGTHS = { pa: 255, pn: 99, tn: 50, tr: 35, tid: 35, mn: 50 }.freeze

    VPA_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,}@[A-Za-z][A-Za-z0-9.-]{0,}\z/.freeze
    MERCHANT_CODE_PATTERN = /\A\d{4}\z/.freeze
    REFERENCE_PATTERN = /\A[A-Za-z0-9._-]+\z/.freeze
    ORG_ID_PATTERN = /\A\d{6}\z/.freeze
    NUMERIC_PATTERN = /\A\d+(\.\d+)?\z/.freeze
    TWO_DIGIT_PATTERN = /\A\d{2}\z/.freeze

    # Largest amount we will emit. Per-transaction ceilings are set by the bank
    # and the merchant category, so this only catches obviously bad input.
    MAX_AMOUNT = BigDecimal('10000000000')

    private

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
      raise ValidationError, "#{label} must be at most #{MAX_LENGTHS[key]} characters, got #{value.length}" if value.length > MAX_LENGTHS[key]
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
      raise ValidationError, "merchant_code #{merchant_code.inspect} must be a four-digit ISO 18245 category code" unless value.match?(MERCHANT_CODE_PATTERN)

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
      raise ValidationError, "initiation_mode #{initiation_mode.inspect} must be two digits" unless value.match?(TWO_DIGIT_PATTERN)

      value
    end

    def validate_org_id!(org_id)
      return nil if org_id.nil?

      value = org_id.to_s.strip
      raise ValidationError, "org_id #{org_id.inspect} must be six digits" unless value.match?(ORG_ID_PATTERN)

      value
    end

    def validate_flag!(flag, label)
      return nil if flag.nil?

      case flag
      when true then 'Y'
      when false then 'N'
      else
        value = flag.to_s.strip.upcase
        raise ValidationError, "#{label} must be Y or N, got #{flag.inspect}" unless %w[Y N].include?(value)

        value
      end
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
  end
end
