require 'upi'

RSpec.describe Upi::Generator do
  it 'generates a UPI QR code' do
    generator = Upi::Generator.new(100, 'test@upi', 'Test Name', 'Test Description')
    expect(generator.generate_qr).to include('svg')
  end
end