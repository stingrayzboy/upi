# UPI

The `upi` gem generates UPI payment URIs and QR codes, in PNG or SVG, that conform to the
[NPCI UPI Linking Specification](https://www.npci.org.in/what-we-do/upi/product-overview)
(common URL specification for deep linking and proximity integration).

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

Initialize `Upi::Generator` with the payee details, then call `generate_qr` for a QR code or
`upi_content` for the raw payment URI. Generator instances are immutable and safe to reuse
and share across threads.

### Individual mode (P2P)

```ruby
require 'upi'

generator = Upi::Generator.new(
  upi_id: 'test@upi',
  name: 'Test Name'
)
```

Do not pass `merchant_code` for individual payments; it is omitted entirely.

#### QR code in SVG format

```ruby
svg_content = generator.generate_qr(100, 'Personal Payment', mode: :svg)
File.write('qr_code.svg', svg_content)
```

#### QR code in PNG format

```ruby
png_content = generator.generate_qr(100, 'Personal Payment', mode: :png)
File.binwrite('qr_code.png', png_content)
```

#### Payment URI

`upi_content` returns a UPI URI you can use as the `href` of a "Pay Now" link:

```ruby
payment_url = generator.upi_content(100, 'Personal Payment')
# => "upi://pay?pa=test@upi&pn=Test%20Name&tn=Personal%20Payment&am=100.00&cu=INR"
```

```html
<a href="<%= payment_url %>">Pay Now</a>
```

#### Letting the payer choose the amount

Omit the amount and the `am` tag is left out, so the payer types their own. Never pass `0` for
this — UPI apps reject `am=0`, and the gem raises rather than emit it.

```ruby
generator.upi_content
# => "upi://pay?pa=test@upi&pn=Test%20Name&cu=INR"
```

### Merchant mode (P2M)

Pass a four-digit [ISO 18245](https://en.wikipedia.org/wiki/Merchant_category_code) merchant
category code:

```ruby
generator = Upi::Generator.new(
  upi_id: 'merchant@upi',
  name: 'Test Name',
  merchant_code: '5411'
)
```

A merchant payment that carries an amount **must** also carry a transaction reference (`tr`),
and that reference **must be unique for every payment attempt**. PSPs reject a reference they
have already seen as a duplicate, so a QR code with a hard-coded reference works once and then
silently stops. `Upi::Generator.generate_reference` builds a suitable one:

```ruby
reference = Upi::Generator.generate_reference('ORD')  # => "ORD20260917131656E4BBC91A"

svg_content = generator.generate_qr(
  500, 'Payment for Goods',
  transaction_ref_id: reference,
  transaction_id: 'TXN456',
  url: 'https://merchant.com/payment',
  mode: :svg
)
```

In practice the reference is your own order or invoice number, which is what makes
reconciliation work:

```ruby
generator.upi_content(500, 'Payment for Goods', transaction_ref_id: "ORD#{order.id}")
```

Leaving the amount out produces a static "shop counter" QR, which needs no reference because
the payer supplies a fresh one each time:

```ruby
generator.upi_content
# => "upi://pay?pa=merchant@upi&pn=Test%20Name&mc=5411&cu=INR"
```

### Letting the payer pay at least a minimum

`min_amount` maps to the `mam` tag: the amount becomes editable, down to that floor.

```ruby
generator.upi_content(500, 'Donation', transaction_ref_id: 'ORD90211', min_amount: 100)
# => "upi://pay?pa=merchant@upi&pn=Test%20Name&mc=5411&tr=ORD90211&tn=Donation&am=500.00&mam=100.00&cu=INR"
```

## Parameters

### `Upi::Generator.new`

| Parameter | Required | Notes |
| --- | --- | --- |
| `upi_id:` | yes | Payee VPA, `name@psp`. Max 255 characters. |
| `name:` | yes | Payee name shown on the payer's confirmation screen. Max 99 characters. |
| `currency:` | no | Defaults to `'INR'`, the only value UPI supports. |
| `merchant_code:` | no | Four-digit ISO 18245 category code. Its presence selects merchant mode. |
| `no_url_parse:` | no | Encoding strictness, see [Encoding](#encoding). Defaults to `true`. |

### `#upi_content` and `#generate_qr`

Both take the same payment arguments; `generate_qr` adds the rendering ones.

| Parameter | Notes |
| --- | --- |
| `amount` | First positional. Omit to let the payer choose. Max two decimal places. |
| `note` | Second positional. Maps to `tn`. Max 50 characters. |
| `transaction_ref_id:` | `tr`. Mandatory for merchant payments with an amount. Max 35 alphanumeric characters. |
| `transaction_id:` | `tid`, PSP-generated when present. Max 35 alphanumeric characters. |
| `url:` | `http(s)` URL with further transaction detail. |
| `min_amount:` | `mam`. Makes the amount editable down to this floor. |
| `initiation_mode:` | `mode`. Opt-in, see [Initiation mode](#initiation-mode). |
| `mode:` | `generate_qr` only. `:svg` (default) or `:png`. |
| `level:` | `generate_qr` only. QR error correction: `:l`, `:m` (default), `:q`, `:h`. |

Any other keyword to `generate_qr` is passed through to the renderer, so
`module_px_size:`, `border_modules:`, `color:` and the rest of the
[rqrcode](https://github.com/whomwah/rqrcode) options still work:

```ruby
generator.generate_qr(100, 'Tea', mode: :png, module_px_size: 12, color: '333')
```

## Amounts

Amounts are normalised to the two-decimal format UPI requires, and anything that cannot be
represented that way raises rather than producing an unpayable QR code.

```ruby
generator.upi_content(100)            # => "...&am=100.00&..."
generator.upi_content(1499.5)         # => "...&am=1499.50&..."
generator.upi_content(0.1 + 0.2)      # => "...&am=0.30&..."     float noise is discarded
generator.upi_content(BigDecimal('99.9'))

generator.upi_content(100.456)        # raises Upi::ValidationError, more than two decimals
generator.upi_content(0)              # raises Upi::ValidationError, UPI apps reject am=0
```

Pass a `String` or `BigDecimal` when the amount comes from a currency column, so no float ever
touches it.

## Validation

Every field is checked against the specification before a URI is built, and a failure raises
`Upi::ValidationError` (a subclass of `Upi::Error`). This is deliberate: an invalid UPI URI
still produces a perfectly scannable QR code, so without validation the only symptom is a
payment that fails later, in the payer's app.

```ruby
Upi::Generator.new(upi_id: 'not-a-vpa', name: 'X')
# Upi::ValidationError: upi_id "not-a-vpa" is not a valid UPI address (expected 'name@psp')
```

## Encoding

Values are percent-encoded per RFC 3986, with spaces as `%20`, matching the example URIs in
the specification. `no_url_parse` selects how aggressive that is:

* `true` (default) encodes down to the unreserved set.
* `false` leaves URL-safe punctuation such as `:` and `/` readable.

Either way the characters that would corrupt the query string — `&`, `#`, `%`, `+` and space —
are always escaped, so a note like `Tea & Coffee #12` can never truncate the URI or forge
another parameter. Redirect URLs keep their `://` readable in both modes.

## Initiation mode

The specification lists a `mode` tag (`01` for QR, `04` for intent). It is left out by default,
since most PSP apps accept a URI without it and existing integrations rely on that. Opt in when
you want it:

```ruby
generator.upi_content(500, 'Goods', transaction_ref_id: 'ORD1',
                      initiation_mode: Upi::Generator::MODE_QR)
# => "...&cu=INR&mode=01"
```

Signed QR codes (`mode=02`, requiring the `sign` and `orgid` tags) are not supported.

## Upgrading from 2.x

3.0 changes the generated URI so that it complies with the specification. See the
[CHANGELOG](CHANGELOG.md) for the full list. The changes most likely to affect you:

* Spaces encode as `%20`, not `+`, and parameters are emitted in the specification's order, so
  any test asserting an exact URI string needs updating.
* Amounts always carry two decimals: `am=100` is now `am=100.00`.
* Calling without an amount no longer emits `am=0&tn=`; both tags are omitted.
* Invalid input now raises `Upi::ValidationError` instead of silently producing a broken QR
  code. Merchant payments with an amount now require `transaction_ref_id`.
* `#params` returns the frozen constructor parameters rather than the last call's state.
* PNG output is sized by module rather than pinned to 300px, so images vary in size with the
  payload. Pass `size:` or `module_px_size:` to control it.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/stingrayzboy/upi. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/stingrayzboy/upi/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Upi project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/stingrayzboy/upi/blob/master/CODE_OF_CONDUCT.md).
