# frozen_string_literal: true

require 'openssl'

module Upi
  # Signs intents and QR codes per section 1.3 of the UPI Linking Specification.
  #
  # The merchant signs the whole intent string with its private key using SHA256
  # with RSA, base64-encodes the result, and appends it as the `sign` tag, which
  # must be the last tag in the URI. The payer's PSP verifies it against the
  # public key the acquiring bank registered with UPI.
  #
  #   signer = Upi::Signer.new(File.read('merchant.pem'))
  #   generator = Upi::Generator.new(upi_id: 'merchant@upi', name: 'Store',
  #                                  merchant_code: '5499', org_id: '000000',
  #                                  signer: signer)
  #   generator.generate_qr(500, 'Order 1', transaction_ref_id: ref,
  #                         initiation_mode: Upi::Generator::MODE_SECURE_QR)
  #
  # Signing is entirely local; nothing here talks to NPCI. What it cannot do for
  # you is the operational half: the keypair has to be registered with your
  # acquiring bank before any PSP will accept the signature.
  #
  # Verification is deliberately not offered. That is the payer PSP's job, done
  # against a daily-refreshed cache of registered merchant keys, and a merchant
  # gem is in no position to do it meaningfully.
  class Signer
    # The specification names "SHA256 with RSA512". That maps to a SHA-256
    # digest signed with RSA; the trailing number refers to the signature size
    # in bytes for a 4096-bit key, not to a digest variant.
    DIGEST = OpenSSL::Digest::SHA256

    MINIMUM_KEY_BITS = 2048

    attr_reader :key

    # @param key [OpenSSL::PKey::RSA, String] an RSA private key, or the PEM or
    #   DER text of one
    # @param passphrase [String, nil] passphrase for an encrypted PEM
    def initialize(key, passphrase: nil)
      @key = coerce_key(key, passphrase)

      raise ValidationError, 'signing requires an RSA private key, got a public key' unless @key.private?

      return unless @key.n.num_bits < MINIMUM_KEY_BITS

      raise ValidationError, "signing key must be at least #{MINIMUM_KEY_BITS} bits, got #{@key.n.num_bits}"
    end

    # @param content [String] the complete URI, without the `sign` tag
    # @return [String] base64-encoded signature
    def sign(content)
      # pack('m0') is strict base64 without the stdlib base64 dependency,
      # which became a bundled gem in Ruby 3.4.
      [key.sign(DIGEST.new, content)].pack('m0')
    end

    # Verifies a signature against this key, for round-tripping in your own
    # tests. Not a substitute for PSP-side verification.
    def verify(content, signature)
      key.verify(DIGEST.new, signature.to_s.unpack1('m'), content)
    rescue ArgumentError
      false
    end

    private

    def coerce_key(key, passphrase)
      return key if key.is_a?(OpenSSL::PKey::RSA)

      OpenSSL::PKey::RSA.new(key.to_s, *[passphrase].compact)
    rescue OpenSSL::PKey::RSAError => e
      raise ValidationError, "could not read the signing key: #{e.message}"
    end
  end
end
