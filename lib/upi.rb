# frozen_string_literal: true

require 'rqrcode'
require_relative "upi/version"

module Upi
  class Generator
    def initialize(amount, upi_id, name, description = '', currency = 'INR')
      @amount = amount
      @upi_id = upi_id
      @name = name
      @description = description
      @currency = currency
    end

    def generate_qr
      content = upi_content
      qrcode = RQRCode::QRCode.new(content)
      qrcode.as_svg(
        color: '000',
        shape_rendering: 'crispEdges',
        module_size: 11
      )
    end

    private

    def upi_content
      "upi://pay?pa=#{@upi_id}&pn=#{@name}&am=#{@amount}&cu=#{@currency}&tn=#{@description}"
    end
  end

  class Error < StandardError; end
  # Your code goes here...
end
