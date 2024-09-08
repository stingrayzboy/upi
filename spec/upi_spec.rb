# frozen_string_literal: true

require 'upi'

RSpec.describe Upi::Generator do
  context 'Individual QR Code' do
    let(:individual_params) do
      {
        upi_id: 'test@upi',
        name: 'Test User'
      }
    end

    describe '#initialize' do
      it 'initializes with correct attributes' do
        generator = Upi::Generator.new(**individual_params)

        expect(generator.params[:pa]).to eq('test@upi')
        expect(generator.params[:pn]).to eq('Test User')
        expect(generator.params[:cu]).to eq('INR')
        expect(generator.params[:mc]).to eq(nil)
      end
    end

    describe '#upi_content' do
      it 'generates the correct UPI content for an individual' do
        generator = Upi::Generator.new(**individual_params)
        upi_content = generator.upi_content(100, 'Personal Payment')

        expect(upi_content).to eq('upi://pay?pa=test@upi&pn=Test+User&am=100&cu=INR&tn=Personal+Payment')
      end
    end

    describe '#generate_qr' do
      it 'generates a valid QR code in SVG format for an individual' do
        generator = Upi::Generator.new(**individual_params)
        qr_code_svg = generator.generate_qr

        expect(qr_code_svg).to include('<svg')
        expect(qr_code_svg).to include('xmlns="http://www.w3.org/2000/svg"')
      end

      it 'generates a valid QR code in SVG format for an individual' do
        generator = Upi::Generator.new(**individual_params)
        png_content = generator.generate_qr(mode: :png)

        expect(png_content[0..7]).to eq("\x89PNG\r\n\x1A\n".b)
      end
    end
  end

  context 'Merchant QR Code' do
    let(:merchant_params) do
      {
        upi_id: 'merchant@upi',
        name: 'Merchant Name',
        merchant_code: '1234',
        currency: 'INR'
      }
    end

    describe '#initialize' do
      it 'initializes with correct merchant-specific attributes' do
        generator = Upi::Generator.new(**merchant_params)

        expect(generator.params[:pa]).to eq('merchant@upi')
        expect(generator.params[:pn]).to eq('Merchant Name')
        expect(generator.params[:cu]).to eq('INR')
        expect(generator.params[:mc]).to eq('1234')
      end
    end

    describe '#upi_content' do
      it 'generates the correct UPI content for a merchant' do
        generator = Upi::Generator.new(**merchant_params)
        upi_content = generator.upi_content(500, 'Payment for Goods', transaction_ref_id: 'REF123', transaction_id: 'TXN456', url: 'https://merchant.com/payment')
        expect(upi_content).to eq(
          'upi://pay?pa=merchant@upi&pn=Merchant+Name&am=500&cu=INR&tn=Payment+for+Goods&mc=1234&tr=REF123&tid=TXN456&url=https%3A%2F%2Fmerchant.com%2Fpayment'
        )
      end
    end

    describe '#generate_qr' do
      it 'generates a valid QR code in SVG format for a merchant' do
        generator = Upi::Generator.new(**merchant_params)
        qr_code_svg = generator.generate_qr(500, 'Payment for Goods', transaction_ref_id: 'REF123', transaction_id: 'TXN456', url: 'https://merchant.com/payment')

        expect(qr_code_svg).to include('<svg')
        expect(qr_code_svg).to include('xmlns="http://www.w3.org/2000/svg"')
      end
    end
  end
  context 'no url parse' do
    let(:merchant_params) do
      {
        upi_id: 'merchant@upi',
        name: 'Merchant Name',
        merchant_code: '1234',
        currency: 'INR',
        no_url_parse: false
      }
    end

    describe '#initialize' do
      it 'initializes with correct merchant-specific attributes' do
        generator = Upi::Generator.new(**merchant_params)

        expect(generator.params[:pa]).to eq('merchant@upi')
        expect(generator.params[:pn]).to eq('Merchant Name')
        expect(generator.params[:cu]).to eq('INR')
        expect(generator.params[:mc]).to eq('1234')
        expect(generator.instance_variable_get(:@no_url_parse)).to eq(false)
      end
    end

    describe '#upi_content' do
      it 'generates the correct UPI content for a merchant' do
        generator = Upi::Generator.new(**merchant_params)
        upi_content = generator.upi_content(500, 'Payment for Goods', transaction_ref_id: 'REF123', transaction_id: 'TXN456', url: 'https://merchant.com/payment')
        expect(upi_content).to eq(
          'upi://pay?pa=merchant@upi&pn=Merchant Name&am=500&cu=INR&tn=Payment for Goods&mc=1234&tr=REF123&tid=TXN456&url=https://merchant.com/payment'
        )
      end
    end

    describe '#generate_qr' do
      it 'generates a valid QR code in SVG format for a merchant' do
        generator = Upi::Generator.new(**merchant_params)
        qr_code_svg = generator.generate_qr(500, 'Payment for Goods', transaction_ref_id: 'REF123', transaction_id: 'TXN456', url: 'https://merchant.com/payment')

        expect(qr_code_svg).to include('<svg')
        expect(qr_code_svg).to include('xmlns="http://www.w3.org/2000/svg"')
      end
    end
  end
end
