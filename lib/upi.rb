# frozen_string_literal: true

require 'rqrcode'
require_relative 'upi/version'

module Upi
  # The Generator class is responsible for creating UPI QR codes and payment URLs.
  #
  # You can generate a QR code for a UPI payment in either SVG or PNG format,
  # and also create a UPI payment URL for use in HTML links.
  #
  # Example usage:
  #
  #   generator = Upi::Generator.new(
  #     upi_id: 'test@upi',
  #     name: 'Test Name',
  #     amount: 100,
  #     note: 'Test Description'
  #   )
  #
  #   svg_content = generator.generate_qr(mode: :svg)
  #   png_content = generator.generate_qr(mode: :png)
  #   payment_url = generator.generate_url
  #
  # Parameters:
  # - `upi_id`: The UPI ID of the recipient.
  # - `name`: The name of the recipient.
  # - `amount`: The payment amount (required for UPI transactions).
  # - `currency`: The currency code (default is 'INR').
  # - `note`: An optional note or description for the payment.
  # - `merchant_code`: An optional merchant code.
  # - `transaction_ref_id`: An optional transaction reference ID.
  # - `transaction_id`: An optional transaction ID.
  # - `url`: An optional URL for additional information or payment redirect.
  #
  # @example
  #   generator = Upi::Generator.new(
  #     upi_id: 'test@upi',
  #     name: 'Test Name',
  #     amount: 100
  #   )
  #   svg_content = generator.generate_qr(mode: :svg)
  #   File.write('qr_code.svg', svg_content)
  #
  # @see https://www.upi.gov.in/ for more details on UPI protocol
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

    def generate_qr(mode: :svg)
      content = upi_content
      qrcode = RQRCode::QRCode.new(content)

      case mode
      when :svg
        qrcode.as_svg(
          color: '000',
          shape_rendering: 'crispEdges',
          module_size: 11
        )
      when :png
        png = qrcode.as_png(
          bit_depth: 1,
          border_modules: 4,
          color_mode: ChunkyPNG::COLOR_GRAYSCALE,
          color: 'black',
          file: nil,
          fill: 'white',
          module_px_size: 6, # Adjust size as needed
          resize_exactly_to: false,
          resize_gte_to: false,
          size: 300 # Adjust size as needed
        )
        png.to_s
      else
        raise ArgumentError, "Unsupported mode: #{mode}. Use :svg or :png."
      end
    end

    def upi_content
      # Manually construct the UPI URI string without URI::UPI
      query_string = URI.encode_www_form(params)
      "upi://pay?#{query_string}"
    end
  end

  class Error < StandardError; end
end
