# frozen_string_literal: true

module Upi
  # Base error class for the gem.
  class Error < StandardError; end

  # Raised when supplied details cannot produce a spec-compliant UPI URI.
  #
  # Failing loudly at generation time is deliberate: an invalid UPI URI still
  # produces a perfectly scannable QR code, so the only symptom is a payment
  # that fails in the payer's app, long after the QR was handed out.
  class ValidationError < Error; end

  # Raised when a UPI URI or PSP response cannot be understood.
  class ParseError < Error; end
end
