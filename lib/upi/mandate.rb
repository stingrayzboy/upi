# frozen_string_literal: true

require 'date'
require_relative 'encoding'
require_relative 'rendering'
require_relative 'validations'

module Upi
  # Builds `upi://mandate?...` URIs for UPI AutoPay, the recurring-payment
  # flow layered on top of UPI.
  #
  #   mandate = Upi::Mandate.new(upi_id: 'acme@axis', name: 'Acme Corp',
  #                              merchant_code: '7322')
  #   mandate.mandate_content(
  #     499, 'Monthly plan',
  #     transaction_ref_id: 'SUB-1042',
  #     validity_start: Date.today, validity_end: Date.today.next_year,
  #     recurrence: Upi::Mandate::MONTHLY
  #   )
  #
  # A caveat on provenance: unlike {Upi::Generator}, this is not modelled on the
  # NPCI Linking Specification document, which predates AutoPay and does not
  # describe the mandate tags. It follows the deep link published by PSP
  # aggregators, which agree on the core tags but differ at the edges (some
  # expect `block=Y/N`, others `True/False`; the accepted `mode` values vary).
  # Verify the exact shape against your own PSP before going live, and use
  # {#tags} to inspect what will be emitted.
  class Mandate
    include Validations
    include Rendering

    CURRENCY = Validations::CURRENCY

    # Recurrence patterns (`recur`).
    ONETIME = 'ONETIME'
    DAILY = 'DAILY'
    WEEKLY = 'WEEKLY'
    FORTNIGHTLY = 'FORTNIGHTLY'
    MONTHLY = 'MONTHLY'
    BIMONTHLY = 'BIMONTHLY'
    QUARTERLY = 'QUARTERLY'
    HALFYEARLY = 'HALFYEARLY'
    YEARLY = 'YEARLY'
    # Debited whenever the merchant presents a request, within the mandate's
    # ceiling. The usual choice for usage-based billing.
    ASPRESENTED = 'ASPRESENTED'

    RECURRENCES = [ONETIME, DAILY, WEEKLY, FORTNIGHTLY, MONTHLY, BIMONTHLY,
                   QUARTERLY, HALFYEARLY, YEARLY, ASPRESENTED].freeze

    # Recurrence anchor (`recurtype`).
    ON = 'ON'
    BEFORE = 'BEFORE'
    AFTER = 'AFTER'
    RECURRENCE_TYPES = [ON, BEFORE, AFTER].freeze

    # Amount rules (`amrule`). MAX treats the amount as a ceiling; EXACT debits
    # precisely that amount each time.
    MAX = 'MAX'
    EXACT = 'EXACT'
    AMOUNT_RULES = [MAX, EXACT].freeze

    # Mandate operations (`txnType`).
    CREATE = 'CREATE'
    UPDATE = 'UPDATE'
    REVOKE = 'REVOKE'
    PAUSE = 'PAUSE'
    UNPAUSE = 'UNPAUSE'
    TRANSACTION_TYPES = [CREATE, UPDATE, REVOKE, PAUSE, UNPAUSE].freeze

    # Mandate creation purpose code.
    DEFAULT_PURPOSE = '14'

    DATE_FORMAT = '%d%m%Y'

    PARAM_ORDER = %i[pa pn mc tid tr tn mn am amrule cu validitystart validityend
                     recur recurtype recurvalue purpose rev share block qrexpire
                     txnType mode orgid].freeze
    SIGNATURE_TAG = :sign

    # Keywords that belong to the mandate itself rather than to the renderer.
    MANDATE_KEYWORDS = %i[transaction_ref_id validity_start validity_end recurrence
                          recurrence_type recurrence_value amount_rule transaction_type
                          mandate_name revocable shareable block_funds qr_expiry purpose
                          transaction_id initiation_mode].freeze

    attr_reader :params, :no_url_parse, :signer

    # @param upi_id [String] payee VPA
    # @param name [String] payee name
    # @param merchant_code [String, nil] four-digit ISO 18245 category code
    # @param currency [String] only `'INR'` is supported
    # @param org_id [String, nil] six-digit `orgid`, required when signing
    # @param signer [Upi::Signer, nil] signs every URI this builder produces
    # @param no_url_parse [Boolean] see {Upi::Generator#initialize}
    def initialize(upi_id:, name:, merchant_code: nil, currency: CURRENCY,
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

    # Builds the `upi://mandate?...` URI.
    #
    # @param amount [Numeric, String] the debit amount, or its ceiling under
    #   {MAX}. Required: a mandate with no amount has no meaning.
    # @param note [String, nil] `tn`, max 50 characters
    # @param transaction_ref_id [String] `tr`, your subscription or order id
    # @param validity_start [Date, String] first day the mandate is valid
    # @param validity_end [Date, String] last day the mandate is valid
    # @param recurrence [String] one of {RECURRENCES}
    # @param recurrence_type [String, nil] one of {RECURRENCE_TYPES}
    # @param recurrence_value [Integer, nil] day of the period to debit on
    # @param amount_rule [String] {MAX} or {EXACT}
    # @param transaction_type [String] {CREATE}, {UPDATE}, {REVOKE} and friends
    # @param mandate_name [String, nil] `mn`, shown to the payer
    # @param revocable [Boolean, String, nil] `rev`
    # @param shareable [Boolean, String, nil] `share`
    # @param block_funds [Boolean, String, nil] `block`, for single-block
    #   multi-debit mandates
    # @param qr_expiry [Date, String, nil] `qrexpire`
    # @param purpose [String] two-digit purpose code
    # @param transaction_id [String, nil] `tid`
    # @param initiation_mode [String, nil] `mode`
    # @return [String]
    def mandate_content(amount, note = nil, **options)
      content = serialize(build_fields(amount, note, **options))
      signer ? "#{content}&#{SIGNATURE_TAG}=#{encode(signer.sign(content))}" : content
    end

    # Renders the mandate URI as a QR code. Takes the same arguments as
    # {#mandate_content}, plus the renderer options of
    # {Upi::Generator#generate_qr}.
    def generate_qr(amount, note = nil, mode: :svg, level: :m, **options)
      mandate_options, render_options = options.partition { |key, _| MANDATE_KEYWORDS.include?(key) }
                                               .map(&:to_h)

      render(mandate_content(amount, note, **mandate_options), mode, level, render_options)
    end

    # The tags this builder would emit, in emission order, for checking against
    # your PSP's own documentation. Takes the same arguments as
    # {#mandate_content}.
    #
    # @return [Hash{Symbol => String}]
    def tags(amount, note = nil, **options)
      fields = build_fields(amount, note, **options)

      PARAM_ORDER.each_with_object({}) do |key, emitted|
        value = fields[key]
        emitted[key] = value unless value.nil?
      end
    end

    private

    def serialize(fields)
      query = PARAM_ORDER.map do |key|
        next if key == :pa

        value = fields[key]
        "#{key}=#{encode(value)}" unless value.nil?
      end.compact

      "upi://mandate?pa=#{fields[:pa]}&#{query.join("&")}"
    end

    def build_fields(amount, note = nil, transaction_ref_id:, validity_start:, validity_end:,
                     recurrence:, recurrence_type: nil, recurrence_value: nil,
                     amount_rule: MAX, transaction_type: CREATE, mandate_name: nil,
                     revocable: nil, shareable: nil, block_funds: nil, qr_expiry: nil,
                     purpose: DEFAULT_PURPOSE, transaction_id: nil, initiation_mode: nil)
      params
        .merge(identity_fields(note, transaction_ref_id, transaction_id, mandate_name))
        .merge(amount_fields(amount, amount_rule))
        .merge(schedule_fields(validity_start, validity_end, recurrence, recurrence_type,
                               recurrence_value, qr_expiry))
        .merge(option_fields(purpose, revocable, shareable, block_funds, transaction_type,
                             initiation_mode))
    end

    def identity_fields(note, transaction_ref_id, transaction_id, mandate_name)
      reference = validate_reference!(transaction_ref_id, :tr, 'transaction_ref_id')
      raise ValidationError, 'transaction_ref_id is required for a mandate' if reference.nil?

      {
        tid: validate_reference!(transaction_id, :tid, 'transaction_id'),
        tr: reference,
        tn: presence(validate_text!(note, :tn, 'note')),
        mn: presence(validate_text!(mandate_name, :mn, 'mandate_name'))
      }
    end

    def amount_fields(amount, amount_rule)
      normalized = normalize_amount(amount, 'amount')
      raise ValidationError, 'amount is required for a mandate' if normalized.nil?

      { am: normalized, amrule: validate_enum!(amount_rule, AMOUNT_RULES, 'amount_rule') }
    end

    def schedule_fields(validity_start, validity_end, recurrence, recurrence_type,
                        recurrence_value, qr_expiry)
      ensure_ordered!(validity_start, validity_end)

      {
        validitystart: format_date!(validity_start, 'validity_start'),
        validityend: format_date!(validity_end, 'validity_end'),
        recur: validate_enum!(recurrence, RECURRENCES, 'recurrence'),
        recurtype: recurrence_type && validate_enum!(recurrence_type, RECURRENCE_TYPES, 'recurrence_type'),
        recurvalue: validate_recurrence_value!(recurrence_value),
        qrexpire: qr_expiry && format_date!(qr_expiry, 'qr_expiry')
      }
    end

    def option_fields(purpose, revocable, shareable, block_funds, transaction_type, initiation_mode)
      {
        purpose: validate_purpose!(purpose),
        rev: validate_flag!(revocable, 'revocable'),
        share: validate_flag!(shareable, 'shareable'),
        block: validate_flag!(block_funds, 'block_funds'),
        txnType: validate_enum!(transaction_type, TRANSACTION_TYPES, 'transaction_type'),
        mode: validate_initiation_mode!(initiation_mode)
      }
    end

    def validate_enum!(value, allowed, label)
      return nil if value.nil?

      normalized = value.to_s.strip.upcase
      raise ValidationError, "#{label} #{value.inspect} must be one of #{allowed.join(", ")}" unless allowed.include?(normalized)

      normalized
    end

    def validate_recurrence_value!(value)
      return nil if value.nil?

      normalized = value.to_s.strip
      raise ValidationError, "recurrence_value #{value.inspect} must be a positive integer" unless normalized.match?(/\A\d+\z/)

      normalized
    end

    def validate_purpose!(purpose)
      return nil if purpose.nil?

      value = purpose.to_s.strip.upcase
      raise ValidationError, "purpose #{purpose.inspect} must be two characters" unless value.match?(/\A[A-Z0-9]{2}\z/)

      value
    end

    def format_date!(date, label)
      case date
      when Date, DateTime, Time then date.strftime(DATE_FORMAT)
      when String
        value = date.strip
        return value if value.match?(/\A\d{8}\z/)

        begin
          Date.parse(value).strftime(DATE_FORMAT)
        rescue ArgumentError
          raise ValidationError, "#{label} #{date.inspect} is not a date (expected a Date or DDMMYYYY)"
        end
      else
        raise ValidationError, "#{label} must be a Date or a DDMMYYYY string, got #{date.class}"
      end
    end

    def ensure_ordered!(start_date, end_date)
      first = coerce_date(start_date)
      last = coerce_date(end_date)
      return if first.nil? || last.nil? || first <= last

      raise ValidationError, "validity_start #{first} must not be after validity_end #{last}"
    end

    def coerce_date(value)
      case value
      when Date, DateTime then value.to_date
      when Time then value.to_date
      when String then (Date.strptime(value.strip, DATE_FORMAT) if value.strip.match?(/\A\d{8}\z/)) || Date.parse(value)
      end
    rescue ArgumentError
      nil
    end

    def encode(value)
      Encoding.encode(value, lenient: !no_url_parse)
    end
  end
end
