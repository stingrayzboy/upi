# frozen_string_literal: true

require 'rqrcode'
require 'chunky_png'
require 'uri'
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
  #     name: 'Test Name'
  #   )
  #
  #   svg_content = generator.generate_qr(100, 'Personal Payment', mode: :svg)
  #   png_content = generator.generate_qr(100, 'Personal Payment', mode: :png)
  #   payment_url = generator.upi_content(100, 'Personal Payment')
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
  #     name: 'Test Name'
  #   )
  #   svg_content = generator.generate_qr(100, 'Personal Payment', mode: :svg)
  #   File.write('qr_code.svg', svg_content)
  #
  # @see https://www.npci.org.in/what-we-do/upi/product-overview for more details on UPI protocol
  class Generator
    attr_reader :params

    def initialize(upi_id:, name:, currency: 'INR', merchant_code: '0000')
      @params = {
        pa: upi_id,
        pn: name,
        am: '',
        cu: currency,
        tn: '',
        mc: merchant_code,
        tr: nil,
        tid: nil,
        url: nil
      }.compact
    end

    def generate_qr(amount = '0', note = '', transaction_ref_id: nil, transaction_id: nil, url: nil, mode: :svg)
      content = upi_content(amount, note, transaction_ref_id: transaction_ref_id, transaction_id: transaction_id, url: url)
      qrcode = RQRCode::QRCode.new(content)
      generate_transaction(amount, note, transaction_id, transaction_ref_id, url)

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

    def upi_content(amount = '0', note = '', transaction_ref_id: nil, transaction_id: nil, url: nil)
      generate_transaction(amount, note, transaction_id, transaction_ref_id, url)

      # Manually construct the UPI URI string without URI::UPI
      query_string = URI.encode_www_form(params.reject { |_k, v| v.nil? })
      "upi://pay?#{query_string}"
    end

    private

    def generate_transaction(amount, note, transaction_id, transaction_ref_id, url)
      @params[:am] = amount
      @params[:tn] = note
      @params[:tr] = transaction_ref_id
      @params[:tid] = transaction_id
      @params[:url] = url
      @params
    end
  end

  class Error < StandardError; end
end
