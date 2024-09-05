# frozen_string_literal: true

require 'rqrcode'
require_relative "upi/version"

module Upi
  class Generator
    attr_reader :params

    def initialize(upi_id:, name:, amount: nil, currency: 'INR', note: '', merchant_code: nil, transaction_ref_id: nil, transaction_id: nil, url: nil)
      @params = {
        pa: upi_id,
        pn: name,
        am: amount,
        cu: currency,
        tn: note,
        mc: merchant_code,
        tr: transaction_ref_id,
        tid: transaction_id,
        url: url
      }.compact
    end

    def generate_qr
      content = upi_content
      qrcode = RQRCode::QRCode.new(content)

      # Output SVG format QR code
      qrcode.as_svg(
        color: '000',
        shape_rendering: 'crispEdges',
        module_size: 11
      )
    end

    private

    def upi_content
      # Manually construct the UPI URI string without URI::UPI
      query_string = URI.encode_www_form(params)
      "upi://pay?#{query_string}"
    end
  end

  class Error < StandardError; end
  # Your code goes here...
end
