require 'upi'

RSpec.describe Upi do
  it 'generates a UPI QR code' do
    generator = UpiQrCodeGenerator.new(100, 'test@upi', 'Test Name', 'Test Description')
    expect(generator.generate_qr).to include('svg')
  end
end