# frozen_string_literal: true

require 'upi'
require 'date'

RSpec.describe Upi::Mandate do
  let(:mandate) { described_class.new(upi_id: 'acme.corp@axis', name: 'Acme Corp', merchant_code: '7322') }
  let(:required) do
    { transaction_ref_id: 'SUB1042',
      validity_start: Date.new(2026, 10, 1),
      validity_end: Date.new(2027, 9, 30),
      recurrence: described_class::MONTHLY }
  end

  describe '#mandate_content' do
    it 'builds a recurring mandate URI' do
      content = mandate.mandate_content(499, 'Monthly plan', **required.merge(
        recurrence_type: described_class::ON, recurrence_value: 1,
        mandate_name: 'Acme Pro', revocable: true
      ))

      expect(content).to eq(
        'upi://mandate?pa=acme.corp@axis&pn=Acme%20Corp&mc=7322&tr=SUB1042&tn=Monthly%20plan' \
        '&mn=Acme%20Pro&am=499.00&amrule=MAX&cu=INR&validitystart=01102026&validityend=30092027' \
        '&recur=MONTHLY&recurtype=ON&recurvalue=1&purpose=14&rev=Y&txnType=CREATE'
      )
    end

    it 'formats dates as DDMMYYYY' do
      content = mandate.mandate_content(10, **required)

      expect(content).to include('validitystart=01102026', 'validityend=30092027')
    end

    it 'accepts dates already in DDMMYYYY' do
      content = mandate.mandate_content(10, **required.merge(validity_start: '01102026',
                                                             validity_end: '30092027'))

      expect(content).to include('validitystart=01102026', 'validityend=30092027')
    end

    it 'normalises amounts the same way payments do' do
      expect(mandate.mandate_content(1499.5, **required)).to include('am=1499.50')
    end

    it 'maps booleans onto the Y/N flags' do
      content = mandate.mandate_content(10, **required.merge(revocable: true, shareable: false,
                                                             block_funds: false))

      expect(content).to include('rev=Y', 'share=N', 'block=N')
    end

    it 'supports as-presented recurrence for usage billing' do
      expect(mandate.mandate_content(2000, **required.merge(recurrence: described_class::ASPRESENTED)))
        .to include('recur=ASPRESENTED')
    end

    it 'supports revoking an existing mandate' do
      expect(mandate.mandate_content(499, **required.merge(transaction_type: described_class::REVOKE)))
        .to include('txnType=REVOKE')
    end

    it 'defaults to the mandate creation purpose code' do
      expect(mandate.mandate_content(10, **required)).to include('purpose=14')
    end
  end

  describe 'validation' do
    it 'requires an amount' do
      expect { mandate.mandate_content(nil, **required) }
        .to raise_error(Upi::ValidationError, /amount is required/)
    end

    it 'requires a transaction reference' do
      expect { mandate.mandate_content(10, **required.merge(transaction_ref_id: nil)) }
        .to raise_error(Upi::ValidationError, /transaction_ref_id is required/)
    end

    it 'rejects an unknown recurrence' do
      expect { mandate.mandate_content(10, **required.merge(recurrence: 'HOURLY')) }
        .to raise_error(Upi::ValidationError, /must be one of ONETIME/)
    end

    it 'rejects an unknown amount rule' do
      expect { mandate.mandate_content(10, **required.merge(amount_rule: 'SOMETIMES')) }
        .to raise_error(Upi::ValidationError, /must be one of MAX, EXACT/)
    end

    it 'rejects a validity window that ends before it starts' do
      expect do
        mandate.mandate_content(10, **required.merge(validity_start: Date.new(2027, 1, 1),
                                                     validity_end: Date.new(2026, 1, 1)))
      end
        .to raise_error(Upi::ValidationError, /must not be after/)
    end

    it 'rejects an unparseable date' do
      expect { mandate.mandate_content(10, **required.merge(validity_end: 'whenever')) }
        .to raise_error(Upi::ValidationError, /is not a date/)
    end

    it 'rejects a flag that is not Y or N' do
      expect { mandate.mandate_content(10, **required.merge(revocable: 'maybe')) }
        .to raise_error(Upi::ValidationError, /must be Y or N/)
    end

    it 'applies the same amount rules as payments' do
      expect { mandate.mandate_content(10.456, **required) }
        .to raise_error(Upi::ValidationError, /more than two decimal places/)
    end
  end

  describe '#generate_qr' do
    it 'renders SVG' do
      expect(mandate.generate_qr(499, 'Plan', **required)).to include('<svg')
    end

    it 'renders PNG' do
      expect(mandate.generate_qr(499, 'Plan', mode: :png, **required)[0..7]).to eq("\x89PNG\r\n\x1A\n".b)
    end

    it 'separates renderer options from mandate options' do
      small = mandate.generate_qr(499, 'Plan', mode: :png, module_px_size: 4, **required)
      large = mandate.generate_qr(499, 'Plan', mode: :png, module_px_size: 12, **required)

      expect(ChunkyPNG::Image.from_blob(large).width).to be > ChunkyPNG::Image.from_blob(small).width
    end
  end

  describe '#tags' do
    it 'exposes what would be emitted, for checking against a PSP' do
      tags = mandate.tags(499, 'Plan', **required)

      expect(tags[:recur]).to eq('MONTHLY')
      expect(tags[:am]).to eq('499.00')
      expect(tags[:txnType]).to eq('CREATE')
    end
  end
end
