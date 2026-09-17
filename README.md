# UPI

The `upi` gem generates and reads UPI payment URIs and QR codes, in PNG or SVG, conforming to
the [NPCI UPI Linking Specification](https://www.npci.org.in/what-we-do/upi/product-overview)
(common URL specification for deep linking and proximity integration).

| | |
| --- | --- |
| `Upi::Generator` | builds `upi://pay` URIs and QR codes |
| `Upi::Mandate` | builds `upi://mandate` URIs for UPI AutoPay |
| `Upi::Signer` | signs either, for secure QR and intent modes |
| `Upi::Request` | reads a `upi://` URI back apart, to check a QR you received |
| `Upi::Response` | reads the reply a PSP app hands back after a payment |

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
| `org_id:` | no | Six-digit `orgid`. Required when signing. |
| `signer:` | no | A `Upi::Signer`, see [Signed QR codes](#signed-qr-codes-and-intents). |
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

## Reading the PSP's reply

After the payer's app finishes, it hands the merchant app a response. `Upi::Response` reads it:

```ruby
response = Upi::Response.parse(params)   # query string, full callback URL, or a hash

response.success?          # => true
response.transaction_ref   # => "ORD90210"   the tr you sent
response.transaction_id    # => "AXI7d2f..."  the PSP's own id
response.response_code     # => "00"
response.approval_ref_no   # => "122321"
```

Field names are matched case-insensitively, because apps vary the casing, and both `""` and the
literal string `"null"` become `nil`.

A payment still in flight reports `pending?` rather than failing:

```ruby
response.pending?    # true when Status=SUBMITTED, or when no status came back
```

**This is a hint, not settlement.** The specification is explicit: "merchant app must check the
final status with their server/PSP server." Treat `success?` as a prompt to confirm server-side,
never as permission to release goods.

## Reading a QR code you received

`Upi::Request` parses in the other direction, for inspecting someone else's QR:

```ruby
request = Upi.parse('upi://pay?pa=merchant@upi&pn=Test%20Store&mc=5411&tr=ORD1&am=10.50&cu=INR')

request.payee_address   # => "merchant@upi"
request.amount          # => BigDecimal("10.5")
request.merchant?       # => true
request.dynamic?        # => true   carries an amount
request.signed?         # => false
```

Parsing is forgiving where generation is strict: a QR in the wild may well have been built by a
tool that got the encoding wrong, and refusing to read it helps nobody. Problems surface as
warnings instead of exceptions, so you can tell a payer *why* their code will not work:

```ruby
request = Upi.parse('upi://pay?pa=merchant@upi&pn=Test+User&am=0&cu=INR&mc=1234')

request.valid?     # => false
request.warnings
# => ["am=0 is rejected by PSP apps; omit the tag to let the payer enter an amount",
#     "tr is mandatory for merchant transactions carrying an amount, and must be unique per attempt",
#     "the URI contains a + where a space was probably meant; spaces must be %20"]
```

That example is a QR built by this gem before 3.0.0.

## Signed QR codes and intents

The specification defines a signed variant: the merchant signs the whole URI with its private
key, and the payer's PSP verifies it against a public key registered with the acquiring bank.

```ruby
signer = Upi::Signer.new(File.read('merchant.pem'))

generator = Upi::Generator.new(
  upi_id: 'merchant@upi',
  name: 'Acme Store',
  merchant_code: '5499',
  org_id: '000000',      # required when signing
  signer: signer
)

generator.generate_qr(500, 'Order 1', transaction_ref_id: reference,
                      initiation_mode: Upi::Generator::MODE_SECURE_QR)
```

`sign` is emitted as the last tag, as section 1.3 requires, and covers everything before it.

Signing is entirely local — nothing here talks to NPCI. The operational half is not: **your
keypair must be registered with your acquiring bank** before any PSP will accept the signature.
Signature *verification* is deliberately not offered; that is the payer PSP's job, done against
a daily-refreshed cache of registered merchant keys.

## Recurring payments (UPI AutoPay)

`Upi::Mandate` builds `upi://mandate` URIs:

```ruby
mandate = Upi::Mandate.new(upi_id: 'acme.corp@axis', name: 'Acme Corp', merchant_code: '7322')

mandate.mandate_content(
  499, 'Monthly plan',
  transaction_ref_id: 'SUB1042',
  validity_start: Date.new(2026, 10, 1),
  validity_end: Date.new(2027, 9, 30),
  recurrence: Upi::Mandate::MONTHLY,
  recurrence_type: Upi::Mandate::ON,
  recurrence_value: 1
)
# => "upi://mandate?pa=acme.corp@axis&pn=Acme%20Corp&mc=7322&tr=SUB1042&tn=Monthly%20plan
#     &am=499.00&amrule=MAX&cu=INR&validitystart=01102026&validityend=30092027
#     &recur=MONTHLY&recurtype=ON&recurvalue=1&purpose=14&txnType=CREATE"
```

`generate_qr` works the same as on `Upi::Generator`.

| Option | Values |
| --- | --- |
| `recurrence:` | `ONETIME` `DAILY` `WEEKLY` `FORTNIGHTLY` `MONTHLY` `BIMONTHLY` `QUARTERLY` `HALFYEARLY` `YEARLY` `ASPRESENTED` |
| `recurrence_type:` | `ON` `BEFORE` `AFTER` |
| `amount_rule:` | `MAX` (a ceiling, the default) or `EXACT` |
| `transaction_type:` | `CREATE` `UPDATE` `REVOKE` `PAUSE` `UNPAUSE` |
| `revocable:` `shareable:` `block_funds:` | `true`/`false`, emitted as `Y`/`N` |

Dates accept a `Date` or a `DDMMYYYY` string, and the validity window is checked for ordering.

**A caveat on provenance.** Unlike everything else here, this is not modelled on the NPCI
Linking Specification, which predates AutoPay and does not describe the mandate tags. It follows
the deep link published by PSP aggregators, who agree on the core tags but differ at the edges —
some expect `block=Y/N`, others `True/False`, and the accepted `mode` values vary. Check the
exact shape against your own PSP before going live; `#tags` shows you what will be emitted:

```ruby
mandate.tags(499, 'Monthly plan', **options)   # => {pa: "...", recur: "MONTHLY", ...}
```

## Transports beyond QR

The URI is transport agnostic. The same string can be shown as a QR code, fired as an Android
intent, or pushed over NFC, BLE or UHF — only the `mode` tag says which route it took:

```ruby
Upi::Generator::MODE_DEFAULT        # "00"
Upi::Generator::MODE_QR             # "01"
Upi::Generator::MODE_SECURE_QR      # "02"
Upi::Generator::MODE_INTENT         # "04"
Upi::Generator::MODE_SECURE_INTENT  # "05"
Upi::Generator::MODE_NFC            # "06"
Upi::Generator::MODE_BLE            # "07"
Upi::Generator::MODE_UHF            # "08"
Upi::Generator::MODE_SEBI           # "15"
```

Moving the bytes over those transports is your application's job; the gem produces the payload.

## Upgrading

3.1 is purely additive: everything new lives in classes that did not exist before, and existing
`Upi::Generator` behaviour is unchanged. The gem is now several files under `lib/upi/`, but
`require 'upi'` still loads everything.

### From 2.x

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
