# UPI

The `upi` gem allows you to generate UPI QR codes for user-to-user payments. It supports both PNG and SVG formats for QR codes.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'upi'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install upi

## Usage

Generating a QR Code
To generate a UPI QR code, you need to initialize the Upi::Generator class with the required parameters and call the generate_qr method.

### Example

Individual Mode:

### Create a new UPI QR code generator instance
```ruby
require 'upi'

generator = Upi::Generator.new(
  upi_id: 'test@upi',
  name: 'Test Name'
)

# NOTE: For Individual Mode the Merchant Code is always 0000 which the code handles by default

```

### Generate QR code in SVG format
```ruby
svg_content = generator.generate_qr(100, 'Personal Payment', mode: :svg)
File.write('qr_code.svg', svg_content)
```

### Generate QR code in PNG format
```ruby
png_content = generator.generate_qr(100, 'Personal Payment', mode: :png)
File.binwrite('qr_code.png', png_content)
```

### Generating a Payment URL
You can generate a UPI payment URL suitable for use in HTML links by using the generate_url method. This URL can be used as the href attribute in a "Pay Now" button or link.

```ruby
# Generate UPI payment URL
payment_url = generator.upi_content(100, 'Personal Payment')
puts payment_url

# The generate_url method returns a UPI URI string that can be used as a link in your HTML:
```

```html
<a href="<%= payment_url %>">Pay Now</a>
```

Merchant Mode:

### Create a new UPI QR code generator instance
```ruby
require 'upi'

generator = Upi::Generator.new(
  upi_id: 'test@upi',
  name: 'Test Name',
  merchant_code: '1234',
  currency: 'INR'
)

# NOTE: For Merchant Mode the Merchant Code needs to be set explicitly

```

### Generate QR code in SVG format
```ruby
svg_content = generator.generate_qr(500, 'Payment for Goods', transaction_ref_id: 'REF123', transaction_id: 'TXN456', url: 'https://merchant.com/payment', mode: :svg)
File.write('qr_code_merchant.svg', svg_content)
```

### Generate QR code in PNG format
```ruby
png_content = generator.generate_qr(500, 'Payment for Goods', transaction_ref_id: 'REF123', transaction_id: 'TXN456', url: 'https://merchant.com/payment', mode: :png)
File.binwrite('qr_code_merchant.png', png_content)
```

### Generating a Payment URL
You can generate a UPI payment URL suitable for use in HTML links by using the generate_url method. This URL can be used as the href attribute in a "Pay Now" button or link.


```ruby
# Generate UPI payment URL
payment_url = generator.upi_content(500, 'Payment for Goods', transaction_ref_id: 'REF123', transaction_id: 'TXN456', url: 'https://merchant.com/payment')
puts payment_url

# The generate_url method returns a UPI URI string that can be used as a link in your HTML:
```

```html
<a href="<%= payment_url %>">Pay Now</a>
```

#### In the example above:

* Replace `'test@upi'` with the UPI ID of the recipient.
* Replace `'Test Name'` with the recipient's name.
* The `amount` parameter specifies the payment amount.
* `note` is an optional field to include additional information.
Parameters
* upi_id: The UPI ID of the recipient.
* name: The name of the recipient.
* amount: The amount for the payment (required for UPI transactions).
* currency: Currency code (default is 'INR').
* note: Additional note or description for the payment.
* merchant_code: Optional merchant code.
* transaction_ref_id: Optional transaction reference ID.
* transaction_id: Optional transaction ID.
* url: Optional URL for additional information or payment redirect.

#### Handling PNG and SVG
You can specify the format of the QR code by using the mode parameter:

* mode: :svg generates an SVG format QR code.
* mode: :png generates a PNG format QR code.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/stingrayzboy/upi. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/upi/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Upi project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/stingrayzboy/upi/blob/master/CODE_OF_CONDUCT.md).
