# frozen_string_literal: true

require 'upi'

RSpec.describe Upi::Response do
  # The three examples printed in section 1.4 of the specification.
  spec_success = 'txnId=abcdefghijklmnopqrstuvwxyz123456789&responseCode=00&' \
                 'ApprovalRefNo=122321&Status=SUCCESS&txnRef=6655443322'
  spec_empty_approval = 'txnId=abcdefghijklmnopqrstuvwxyz123451234&responseCode=ZM&' \
                        'ApprovalRefNo=&Status=FAILURE&txnRef=6655443322'
  spec_null_approval = 'txnId=abcdefghijklmnopqrstuvwxyz123454321&responseCode=Y1&' \
                       'ApprovalRefNo=null&Status=FAILURE&txnRef=6655443322'

  describe '.parse' do
    it 'reads the successful example from the specification' do
      response = described_class.parse(spec_success)

      expect(response.transaction_id).to eq('abcdefghijklmnopqrstuvwxyz123456789')
      expect(response.response_code).to eq('00')
      expect(response.approval_ref_no).to eq('122321')
      expect(response.status).to eq('SUCCESS')
      expect(response.transaction_ref).to eq('6655443322')
      expect(response).to be_success
      expect(response).not_to be_failure
      expect(response).not_to be_pending
    end

    it 'reads the failure examples from the specification' do
      [spec_empty_approval, spec_null_approval].each do |raw|
        response = described_class.parse(raw)

        expect(response).to be_failure
        expect(response).not_to be_success
        expect(response.approval_ref_no).to be_nil
      end
    end

    it 'treats the string "null" as absent rather than as a value' do
      expect(described_class.parse(spec_null_approval).approval_ref_no).to be_nil
    end

    it 'accepts a full callback URL' do
      response = described_class.parse('https://shop.example.com/cb?Status=SUCCESS&txnRef=A1')

      expect(response).to be_success
      expect(response.transaction_ref).to eq('A1')
    end

    it 'accepts an already-parsed params hash' do
      expect(described_class.parse('Status' => 'SUCCESS', 'txnRef' => 'A1')).to be_success
    end

    it 'matches field names case-insensitively, as apps vary' do
      expect(described_class.parse('status=success&txnref=A1')).to be_success
      expect(described_class.parse('TXNID=X&STATUS=FAILURE').transaction_id).to eq('X')
    end

    it 'percent-decodes values' do
      expect(described_class.parse('Status=SUCCESS&txnRef=A%201').transaction_ref).to eq('A 1')
    end

    it 'falls back to the response code when no status is present' do
      expect(described_class.parse('responseCode=00&txnRef=A1')).to be_success
      expect(described_class.parse('responseCode=ZM&txnRef=A1')).not_to be_success
    end

    it 'treats an in-flight payment as pending rather than as a failure' do
      response = described_class.parse('Status=SUBMITTED&txnRef=A1')

      expect(response).to be_submitted
      expect(response).to be_pending
      expect(response).not_to be_success
      expect(response).not_to be_failure
    end

    it 'raises when nothing resembling a response is present' do
      expect { described_class.parse('nothing=here') }.to raise_error(Upi::ParseError, /no UPI response fields/)
      expect { described_class.parse('') }.to raise_error(Upi::ParseError, /empty/)
    end
  end

  describe '#to_h' do
    it 'exposes every field' do
      expect(described_class.parse(spec_success).to_h).to eq(
        transaction_id: 'abcdefghijklmnopqrstuvwxyz123456789',
        response_code: '00',
        approval_ref_no: '122321',
        status: 'SUCCESS',
        transaction_ref: '6655443322'
      )
    end
  end

  it 'is reachable through the module shorthand' do
    expect(Upi.parse_response(spec_success)).to be_success
  end
end
