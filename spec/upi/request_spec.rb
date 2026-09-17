# frozen_string_literal: true

require 'upi'

RSpec.describe Upi::Request do
  describe '.parse' do
    it 'reads the tags out of a payment URI' do
      request = described_class.parse(
        'upi://pay?pa=merchant@upi&pn=Test%20Store&mc=5411&tr=ORD1&tid=T1&' \
        'tn=Order%201&am=10.50&cu=INR&url=https://shop.example.com&mode=01'
      )

      expect(request).to be_pay
      expect(request.payee_address).to eq('merchant@upi')
      expect(request.payee_name).to eq('Test Store')
      expect(request.merchant_code).to eq('5411')
      expect(request.transaction_ref).to eq('ORD1')
      expect(request.transaction_id).to eq('T1')
      expect(request.note).to eq('Order 1')
      expect(request.amount).to eq(BigDecimal('10.50'))
      expect(request.currency).to eq('INR')
      expect(request.url).to eq('https://shop.example.com')
      expect(request.initiation_mode).to eq('01')
    end

    it 'recognises a mandate URI' do
      request = described_class.parse('upi://mandate?pa=acme@axis&pn=Acme&am=100.00&recur=WEEKLY')

      expect(request).to be_mandate
      expect(request).not_to be_pay
      expect(request.tags[:recur]).to eq('WEEKLY')
    end

    it 'rejects anything that is not a UPI URI' do
      expect { described_class.parse('https://example.com') }.to raise_error(Upi::ParseError, /not a upi/)
      expect { described_class.parse('') }.to raise_error(Upi::ParseError, /empty/)
    end

    it 'decodes + as a space by default, since QRs in the wild use it' do
      expect(described_class.parse('upi://pay?pa=a@upi&pn=Test+User').payee_name).to eq('Test User')
    end

    it 'can be told to treat + literally' do
      request = described_class.parse('upi://pay?pa=a@upi&pn=Test+User', plus_as_space: false)

      expect(request.payee_name).to eq('Test+User')
    end

    it 'survives a duplicated tag by keeping the first' do
      expect(described_class.parse('upi://pay?pa=a@upi&am=1.00&am=999.00').amount).to eq(BigDecimal('1'))
    end
  end

  describe 'classification' do
    it 'distinguishes static from dynamic' do
      expect(described_class.parse('upi://pay?pa=a@upi&pn=A&am=10.00')).to be_dynamic
      expect(described_class.parse('upi://pay?pa=a@upi&pn=A')).not_to be_dynamic
    end

    it 'distinguishes merchant from person to person' do
      expect(described_class.parse('upi://pay?pa=a@upi&pn=A&mc=5411')).to be_merchant
      expect(described_class.parse('upi://pay?pa=a@upi&pn=A')).not_to be_merchant
    end

    it 'reports whether the URI is signed' do
      expect(described_class.parse('upi://pay?pa=a@upi&pn=A&sign=abc')).to be_signed
      expect(described_class.parse('upi://pay?pa=a@upi&pn=A')).not_to be_signed
    end
  end

  describe '#warnings' do
    it 'is empty for a sound payment URI' do
      request = described_class.parse('upi://pay?pa=merchant@upi&pn=Store&mc=5411&tr=ORD1&am=10.00&cu=INR')

      expect(request.warnings).to be_empty
      expect(request).to be_valid
    end

    it 'diagnoses a QR built by a pre-3.0 version of this gem' do
      request = described_class.parse('upi://pay?pa=merchant@upi&pn=Test+User&am=0&cu=INR&tn=&mc=1234')

      expect(request).not_to be_valid
      expect(request.warnings).to include(a_string_matching(/am=0 is rejected/))
      expect(request.warnings).to include(a_string_matching(/tr is mandatory/))
      expect(request.warnings).to include(a_string_matching(/contains a \+ where a space/))
    end

    it 'flags a malformed payee address' do
      expect(described_class.parse('upi://pay?pa=nope&pn=A').warnings)
        .to include(a_string_matching(/not a valid UPI address/))
    end

    it 'flags a missing payee name' do
      expect(described_class.parse('upi://pay?pa=a@upi').warnings)
        .to include(a_string_matching(/pn \(payee name\) is missing/))
    end

    it 'flags an amount with too many decimals' do
      expect(described_class.parse('upi://pay?pa=a@upi&pn=A&am=1.234').warnings)
        .to include(a_string_matching(/more than two decimal places/))
    end

    it 'flags an unsupported currency' do
      expect(described_class.parse('upi://pay?pa=a@upi&pn=A&cu=USD').warnings)
        .to include(a_string_matching(/only supports INR/))
    end

    it 'flags a bad merchant code' do
      expect(described_class.parse('upi://pay?pa=a@upi&pn=A&mc=12').warnings)
        .to include(a_string_matching(/four-digit merchant category code/))
    end

    it 'flags an over-long note' do
      expect(described_class.parse("upi://pay?pa=a@upi&pn=A&tn=#{"x" * 51}").warnings)
        .to include(a_string_matching(/the limit is 50/))
    end

    it 'flags a non-http url' do
      expect(described_class.parse('upi://pay?pa=a@upi&pn=A&url=javascript:alert(1)').warnings)
        .to include(a_string_matching(%r{must start with http://}))
    end
  end

  describe 'round tripping' do
    it 'reads back what the generator wrote' do
      built = Upi::Generator.new(upi_id: 'a@upi', name: 'Ann Lee').upi_content(25.5, 'Tea & Cake')
      request = described_class.parse(built)

      expect(request.payee_name).to eq('Ann Lee')
      expect(request.note).to eq('Tea & Cake')
      expect(request.amount).to eq(BigDecimal('25.50'))
      expect(request).to be_valid
    end
  end

  it 'is reachable through the module shorthand' do
    expect(Upi.parse('upi://pay?pa=a@upi&pn=A')).to be_pay
  end
end
