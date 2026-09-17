# frozen_string_literal: true

require 'upi'
require 'openssl'

RSpec.describe Upi::Signer do
  # Generating a 2048-bit key is slow enough to be worth doing once.
  let(:key) { self.class.signing_key }
  let(:signer) { described_class.new(key) }

  def self.signing_key
    @signing_key ||= OpenSSL::PKey::RSA.new(2048)
  end

  describe '#sign' do
    it 'returns a base64 signature that verifies against the key' do
      signature = signer.sign('upi://pay?pa=a@upi')

      expect(signature).to match(%r{\A[A-Za-z0-9+/]+=*\z})
      expect(signer.verify('upi://pay?pa=a@upi', signature)).to be(true)
    end

    it 'does not verify against tampered content' do
      signature = signer.sign('upi://pay?pa=a@upi&am=10.00')

      expect(signer.verify('upi://pay?pa=a@upi&am=1.00', signature)).to be(false)
    end
  end

  describe '.new' do
    it 'accepts a PEM string' do
      expect(described_class.new(key.to_pem).sign('x')).to be_a(String)
    end

    it 'rejects a public key' do
      expect { described_class.new(key.public_key) }
        .to raise_error(Upi::ValidationError, /private key/)
    end

    it 'rejects a key below 2048 bits' do
      expect { described_class.new(OpenSSL::PKey::RSA.new(1024)) }
        .to raise_error(Upi::ValidationError, /at least 2048 bits/)
    end

    it 'rejects unreadable input' do
      expect { described_class.new('not a key') }
        .to raise_error(Upi::ValidationError, /could not read the signing key/)
    end
  end

  describe 'signed payment URIs' do
    let(:generator) do
      Upi::Generator.new(upi_id: 'bivek@npci', name: 'bivek rath', merchant_code: '9999',
                         org_id: '000000', signer: signer)
    end
    let(:uri) do
      generator.upi_content(10, 'Pay to mystar store', transaction_ref_id: '4894398cndhcd23',
                                                       transaction_id: 'cxnkjcnkjdfdvjndkjfvn',
                                                       url: 'https://mystar.com',
                                                       initiation_mode: Upi::Generator::MODE_SECURE_QR)
    end

    it 'puts sign last, as section 1.3 requires' do
      expect(uri.split('&').last).to start_with('sign=')
    end

    it 'signs exactly the URI that precedes the sign tag' do
      content, signature = uri.split('&sign=')

      expect(signer.verify(content, Upi::Encoding.decode(signature))).to be(true)
    end

    it 'carries orgid' do
      expect(uri).to include('orgid=000000')
    end

    it 'requires org_id before it will sign' do
      expect { Upi::Generator.new(upi_id: 'a@upi', name: 'X', signer: signer) }
        .to raise_error(Upi::ValidationError, /requires org_id/)
    end

    it 'leaves unsigned generators untouched' do
      plain = Upi::Generator.new(upi_id: 'a@upi', name: 'X')

      expect(plain.upi_content(10)).not_to include('sign=')
    end

    it 'signs mandates too' do
      mandate = Upi::Mandate.new(upi_id: 'acme@axis', name: 'Acme', org_id: '000000', signer: signer)
      content = mandate.mandate_content(10, transaction_ref_id: 'S1',
                                            validity_start: Date.new(2026, 10, 1),
                                            validity_end: Date.new(2027, 9, 30),
                                            recurrence: Upi::Mandate::MONTHLY)

      expect(content.split('&').last).to start_with('sign=')
    end
  end
end
