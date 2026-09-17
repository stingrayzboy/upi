# frozen_string_literal: true

require_relative 'upi/version'
require_relative 'upi/errors'
require_relative 'upi/encoding'
require_relative 'upi/validations'
require_relative 'upi/rendering'
require_relative 'upi/signer'
require_relative 'upi/generator'
require_relative 'upi/mandate'
require_relative 'upi/request'
require_relative 'upi/response'

# Generates and reads UPI payment URIs and QR codes.
#
# Outbound:
#
#   Upi::Generator  builds upi://pay URIs and QR codes
#   Upi::Mandate    builds upi://mandate URIs for UPI AutoPay
#   Upi::Signer     signs either of them for secure QR and intent modes
#
# Inbound:
#
#   Upi::Request    reads a upi:// URI back apart, for checking a QR you received
#   Upi::Response   reads the reply a PSP app hands back after a payment
#
# @see https://www.npci.org.in/what-we-do/upi/product-overview
module Upi
  # Reads a UPI URI back apart. Shorthand for {Upi::Request.parse}.
  #
  # @param uri [String]
  # @return [Upi::Request]
  def self.parse(uri, **options)
    Request.parse(uri, **options)
  end

  # Reads a PSP response. Shorthand for {Upi::Response.parse}.
  #
  # @param input [String, Hash]
  # @return [Upi::Response]
  def self.parse_response(input, **options)
    Response.parse(input, **options)
  end
end
