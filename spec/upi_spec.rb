# frozen_string_literal: true

require 'upi'

RSpec.describe Upi::Generator do
  let(:individual_params) { { upi_id: 'test@upi', name: 'Test User' } }
  let(:merchant_params) do
    { upi_id: 'merchant@upi', name: 'Merchant Name', merchant_code: '1234', currency: 'INR' }
  end

  context 'Individual QR Code' do
    describe '#initialize' do
      it 'initializes with correct attributes' do
        generator = described_class.new(**individual_params)

        expect(generator.params[:pa]).to eq('test@upi')
        expect(generator.params[:pn]).to eq('Test User')
        expect(generator.params[:cu]).to eq('INR')
        expect(generator.params[:mc]).to eq(nil)
      end
    end

    describe '#upi_content' do
      it 'generates the correct UPI content for an individual' do
        generator = described_class.new(**individual_params)

        expect(generator.upi_content(100, 'Personal Payment')).to eq(
          'upi://pay?pa=test@upi&pn=Test%20User&tn=Personal%20Payment&am=100.00&cu=INR'
        )
      end
    end

    describe '#generate_qr' do
      it 'generates a valid QR code in SVG format for an individual' do
        qr_code_svg = described_class.new(**individual_params).generate_qr

        expect(qr_code_svg).to include('<svg')
        expect(qr_code_svg).to include('xmlns="http://www.w3.org/2000/svg"')
      end

      it 'generates a valid QR code in PNG format for an individual' do
        png_content = described_class.new(**individual_params).generate_qr(mode: :png)

        expect(png_content[0..7]).to eq("\x89PNG\r\n\x1A\n".b)
      end

      it 'rejects an unsupported output mode' do
        generator = described_class.new(**individual_params)

        expect { generator.generate_qr(mode: :gif) }.to raise_error(ArgumentError, /Unsupported mode/)
      end

      it 'rejects a mistyped payment keyword rather than passing it to the renderer' do
        generator = described_class.new(**individual_params)

        expect { generator.generate_qr(100, 'x', transaction_ref: 'ORD1') }
          .to raise_error(ArgumentError, /unknown keyword: :transaction_ref/)
      end

      # Checked before the payload is built, so the typo names itself instead of
      # surfacing as the missing-field error the typo happens to cause.
      it 'reports a mistyped keyword ahead of the field it fails to set' do
        merchant = described_class.new(**merchant_params)

        expect { merchant.generate_qr(500, 'x', transaction_ref: 'ORD1') }
          .to raise_error(ArgumentError, /unknown keyword: :transaction_ref/)
      end

      it 'rejects an unsupported output mode before building anything' do
        merchant = described_class.new(**merchant_params)

        expect { merchant.generate_qr(500, 'x', mode: :gif) }
          .to raise_error(ArgumentError, /Unsupported mode/)
      end

      it 'passes renderer options through' do
        generator = described_class.new(**individual_params)
        small = generator.generate_qr(100, 'Tea', mode: :png, module_px_size: 4)
        large = generator.generate_qr(100, 'Tea', mode: :png, module_px_size: 12)

        expect(ChunkyPNG::Image.from_blob(large).width).to be > ChunkyPNG::Image.from_blob(small).width
      end

      it 'grows the PNG with the payload instead of shrinking the modules' do
        short = described_class.new(**individual_params).generate_qr(100, 'Tea', mode: :png)
        long = described_class.new(**merchant_params)
                              .generate_qr(1499.50, 'Order 90210 for Ashok Kumar', transaction_ref_id: 'ORD2026000090210',
                                                                                   transaction_id: 'TXN8f3c1d9e4b2a',
                                                                                   url: 'https://store.example.com/orders/90210',
                                                                                   mode: :png)

        expect(ChunkyPNG::Image.from_blob(long).width).to be > ChunkyPNG::Image.from_blob(short).width
      end
    end
  end

  context 'Merchant QR Code' do
    describe '#initialize' do
      it 'initializes with correct merchant-specific attributes' do
        generator = described_class.new(**merchant_params)

        expect(generator.params[:pa]).to eq('merchant@upi')
        expect(generator.params[:pn]).to eq('Merchant Name')
        expect(generator.params[:cu]).to eq('INR')
        expect(generator.params[:mc]).to eq('1234')
      end
    end

    describe '#upi_content' do
      it 'generates the correct UPI content for a merchant' do
        generator = described_class.new(**merchant_params)
        upi_content = generator.upi_content(500, 'Payment for Goods', transaction_ref_id: 'REF123',
                                                                      transaction_id: 'TXN456',
                                                                      url: 'https://merchant.com/payment')

        expect(upi_content).to eq(
          'upi://pay?pa=merchant@upi&pn=Merchant%20Name&mc=1234&tid=TXN456&tr=REF123' \
          '&tn=Payment%20for%20Goods&am=500.00&cu=INR&url=https://merchant.com/payment'
        )
      end
    end

    describe '#generate_qr' do
      it 'generates a valid QR code in SVG format for a merchant' do
        qr_code_svg = described_class.new(**merchant_params)
                                     .generate_qr(500, 'Payment for Goods', transaction_ref_id: 'REF123',
                                                                            transaction_id: 'TXN456',
                                                                            url: 'https://merchant.com/payment')

        expect(qr_code_svg).to include('<svg')
        expect(qr_code_svg).to include('xmlns="http://www.w3.org/2000/svg"')
      end
    end
  end

  context 'no url parse' do
    let(:lenient_params) { merchant_params.merge(no_url_parse: false) }

    describe '#initialize' do
      it 'initializes with correct merchant-specific attributes' do
        generator = described_class.new(**lenient_params)

        expect(generator.params[:pa]).to eq('merchant@upi')
        expect(generator.params[:mc]).to eq('1234')
        expect(generator.no_url_parse).to eq(false)
      end
    end

    describe '#upi_content' do
      it 'leaves URL-safe punctuation readable' do
        generator = described_class.new(**lenient_params)

        expect(generator.upi_content(500, 'Ref a/b:c', transaction_ref_id: 'REF123')).to include('tn=Ref%20a/b:c')
      end

      it 'still escapes the separators that would corrupt the query' do
        generator = described_class.new(**lenient_params)

        expect(generator.upi_content(500, 'Tea & Coffee #12', transaction_ref_id: 'REF123'))
          .to include('tn=Tea%20%26%20Coffee%20%2312')
      end
    end
  end

  # Everything below covers the NPCI UPI Linking Specification rules that a
  # non-compliant URI silently violates: the QR still scans, but the payment
  # fails in the payer's app.
  describe 'specification compliance' do
    let(:generator) { described_class.new(**individual_params) }

    describe 'percent encoding' do
      it 'encodes spaces as %20 rather than +' do
        content = generator.upi_content(100, 'Personal Payment')

        expect(content).to include('pn=Test%20User', 'tn=Personal%20Payment')
        expect(content).not_to include('+')
      end

      it 'escapes separators so a note cannot forge another parameter' do
        content = generator.upi_content(100, 'Tea & Coffee #12')

        expect(content).to include('tn=Tea%20%26%20Coffee%20%2312')
        expect(content).to end_with('&cu=INR')
      end

      it 'leaves the payee address unescaped' do
        expect(generator.upi_content(100)).to include('pa=test@upi')
      end
    end

    describe 'amount formatting' do
      it 'always emits two decimal places' do
        expect(generator.upi_content(100)).to include('am=100.00')
        expect(generator.upi_content(1499.5)).to include('am=1499.50')
        expect(generator.upi_content('100.5')).to include('am=100.50')
      end

      it 'discards floating point representation noise' do
        expect(generator.upi_content(0.1 + 0.2)).to include('am=0.30')
      end

      it 'accepts a BigDecimal' do
        expect(generator.upi_content(BigDecimal('99.9'))).to include('am=99.90')
      end

      it 'refuses to silently round away a third decimal place' do
        expect { generator.upi_content(100.456) }
          .to raise_error(Upi::ValidationError, /more than two decimal places/)
      end

      it 'rejects a non-positive amount' do
        expect { generator.upi_content(0) }.to raise_error(Upi::ValidationError, /greater than zero/)
        expect { generator.upi_content(-5) }.to raise_error(Upi::ValidationError, /greater than zero/)
      end

      it 'rejects a non-numeric amount' do
        expect { generator.upi_content('free') }.to raise_error(Upi::ValidationError, /not a valid number/)
      end

      it 'omits the amount entirely when none is given, rather than sending am=0' do
        content = generator.upi_content

        expect(content).to eq('upi://pay?pa=test@upi&pn=Test%20User&cu=INR')
        expect(content).not_to include('am=')
      end

      it 'omits an empty note rather than sending tn=' do
        expect(generator.upi_content(100, '')).not_to include('tn=')
      end
    end

    describe 'minimum amount' do
      it 'emits mam alongside the amount' do
        expect(generator.upi_content(500, 'Donation', min_amount: 100)).to include('am=500.00&mam=100.00')
      end

      it 'rejects a minimum above the amount' do
        expect { generator.upi_content(100, 'Donation', min_amount: 500) }
          .to raise_error(Upi::ValidationError, /cannot exceed amount/)
      end
    end

    describe 'transaction reference' do
      let(:merchant) { described_class.new(**merchant_params) }

      it 'is mandatory for a merchant transaction carrying an amount' do
        expect { merchant.upi_content(500, 'Payment for Goods') }
          .to raise_error(Upi::ValidationError, /mandatory for merchant transactions/)
      end

      it 'is not required for a static merchant QR with no amount' do
        expect(merchant.upi_content).to eq('upi://pay?pa=merchant@upi&pn=Merchant%20Name&mc=1234&cu=INR')
      end

      it 'is not required for a person to person payment' do
        expect(generator.upi_content(100, 'Splitting lunch')).to include('am=100.00')
      end

      it 'rejects a reference containing spaces' do
        expect { generator.upi_content(100, 'x', transaction_ref_id: 'REF 123') }
          .to raise_error(Upi::ValidationError, /alphanumeric with no spaces/)
      end

      it 'rejects an over-long reference' do
        expect { generator.upi_content(100, 'x', transaction_ref_id: 'R' * 36) }
          .to raise_error(Upi::ValidationError, /at most 35 characters/)
      end
    end

    describe '.generate_reference' do
      it 'produces unique references within the field limit' do
        references = Array.new(500) { described_class.generate_reference }

        expect(references.uniq.size).to eq(500)
        expect(references).to all(satisfy { |r| r.length <= Upi::Generator::MAX_LENGTHS[:tr] })
        expect(references).to all(match(Upi::Generator::REFERENCE_PATTERN))
      end

      it 'accepts a custom prefix' do
        expect(described_class.generate_reference('ORD')).to start_with('ORD')
      end

      it 'rejects a prefix that would break the field' do
        expect { described_class.generate_reference('BAD PREFIX') }.to raise_error(Upi::ValidationError)
      end
    end

    describe 'field validation' do
      it 'rejects a malformed payee address' do
        expect { described_class.new(upi_id: 'not-a-vpa', name: 'X') }
          .to raise_error(Upi::ValidationError, /not a valid UPI address/)
      end

      it 'rejects a merchant code that is not four digits' do
        expect { described_class.new(upi_id: 'a@b', name: 'X', merchant_code: '12') }
          .to raise_error(Upi::ValidationError, /four-digit/)
      end

      it 'rejects a currency other than INR' do
        expect { described_class.new(upi_id: 'a@b', name: 'X', currency: 'USD') }
          .to raise_error(Upi::ValidationError, /only supports/)
      end

      it 'rejects a note longer than the 50 character limit' do
        expect { generator.upi_content(100, 'A' * 51) }
          .to raise_error(Upi::ValidationError, /at most 50 characters/)
      end

      it 'rejects a non-http url' do
        expect { generator.upi_content(100, 'x', url: 'javascript:alert(1)') }
          .to raise_error(Upi::ValidationError, %r{http://})
      end
    end

    describe 'initiation mode' do
      it 'is omitted unless asked for' do
        expect(generator.upi_content(100)).not_to include('mode=')
      end

      it 'is emitted when supplied' do
        expect(generator.upi_content(100, initiation_mode: Upi::Generator::MODE_QR)).to end_with('&mode=01')
      end

      it 'rejects a mode that is not two digits' do
        expect { generator.upi_content(100, initiation_mode: '1') }
          .to raise_error(Upi::ValidationError, /two digits/)
      end
    end

    describe 'parameter order' do
      it 'follows the order used by the specification examples' do
        content = described_class.new(**merchant_params)
                                 .upi_content(10, 'Note', transaction_ref_id: 'TR1', transaction_id: 'TID1',
                                                          min_amount: 5, url: 'https://example.com',
                                                          initiation_mode: '01')
        keys = content.sub('upi://pay?', '').split('&').map { |pair| pair.split('=').first.to_sym }

        expect(keys).to eq(%i[pa pn mc tid tr tn am mam cu url mode])
      end
    end
  end

  describe 'instance state' do
    let(:generator) { described_class.new(**individual_params) }

    it 'does not let one call leak into the next' do
      generator.upi_content(500, 'Invoice 7', transaction_ref_id: 'REFA', transaction_id: 'TIDA')

      expect(generator.upi_content(20, 'Coffee')).to eq(
        'upi://pay?pa=test@upi&pn=Test%20User&tn=Coffee&am=20.00&cu=INR'
      )
    end

    it 'exposes frozen constructor params that calls never mutate' do
      before = generator.params.dup
      generator.upi_content(500, 'Invoice 7', transaction_ref_id: 'REFA')

      expect(generator.params).to be_frozen
      expect(generator.params).to eq(before)
    end

    it 'produces consistent output when shared across threads' do
      results = []
      mutex = Mutex.new

      8.times.map do |thread|
        Thread.new do
          200.times do |n|
            amount = (thread * 1000) + n + 1
            content = generator.upi_content(amount, "Order#{amount}")
            ok = content.include?(format('am=%.2f', amount)) && content.include?("tn=Order#{amount}&")
            mutex.synchronize { results << ok }
          end
        end
      end.each(&:join)

      expect(results.count(false)).to eq(0)
    end
  end
end
