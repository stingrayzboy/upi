# UPI

[![Ruby](https://github.com/stingrayzboy/upi/actions/workflows/main.yml/badge.svg)](https://github.com/stingrayzboy/upi/actions/workflows/main.yml)
[![Gem Version](https://badge.fury.io/rb/upi.svg)](https://rubygems.org/gems/upi)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

**Generate and read UPI payments in Ruby.** QR codes, deep links, recurring mandates, signed
intents, and the responses that come back — built to the
[NPCI UPI Linking Specification](https://www.npci.org.in/what-we-do/upi/product-overview).

```ruby
generator = Upi::Generator.new(upi_id: 'acme@icici', name: 'Acme Store', merchant_code: '5499')

generator.generate_qr(499, "Order #{order.id}",
                      transaction_ref_id: "ORD#{order.id}",
                      mode: :png)
```

## Why this gem

**An invalid UPI URI still produces a perfectly scannable QR code.** There is no error, no
warning, nothing to see. The code scans, the payer's app opens, and *then* the payment fails —
often for some amounts and not others, which is why these bugs are so often written off as
flaky networks or "a PhonePe problem".

This gem's job is to make that class of bug impossible. Every rule below is one that a
hand-rolled string interpolation gets wrong, and each produces a QR code that looks perfect:

| If you build the URI yourself | What actually happens |
| --- | --- |
| `URI.encode_www_form` for the query | spaces become `+`, not `%20`; the payer sees `Acme+Store` |
| `am=#{amount}` with a float | `0.1 + 0.2` emits `am=0.30000000000000004`, which PSPs reject |
| `am=#{amount}` with `1499.5` | one decimal place fails on several legacy bank apps |
| `am=0` when you want the payer to choose | Google Pay and PhonePe reject it; the tag must be omitted |
| a note containing `&` or `#` | forges a parameter, or truncates the rest of the URI silently |
| a fixed `tr` on a printed QR | works once, then every scan is rejected as a duplicate |
| no `tr` on a merchant payment | the PSP's risk engine reads it as a replay and shows "limit exceeded" |

All of that is handled. Anything that cannot be made valid raises at generation time, where you
can see it, rather than failing silently in a stranger's banking app an hour later.

Beyond building payments, the gem reads them: point it at a QR code that is failing in the wild
and it will tell you what is wrong with it.

## Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Concepts worth knowing](#concepts-worth-knowing)
- [Building payments](#building-payments)
- [Rendering QR codes](#rendering-qr-codes)
- [Reading the PSP's reply](#reading-the-psps-reply)
- [Reading a QR code you received](#reading-a-qr-code-you-received)
- [Recurring payments (UPI AutoPay)](#recurring-payments-upi-autopay)
- [Signed QR codes and intents](#signed-qr-codes-and-intents)
- [Transports beyond QR](#transports-beyond-qr)
- [Recipes](#recipes)
- [Troubleshooting](#troubleshooting)
- [API reference](#api-reference)
- [Amounts and money](#amounts-and-money)
- [Specification coverage](#specification-coverage)
- [Compatibility](#compatibility)
- [Upgrading](#upgrading)

## Installation

```ruby
gem 'upi'
```

```console
$ bundle install
```

Or standalone:

```console
$ gem install upi
```

Requires Ruby 2.6 or newer. Runtime dependencies are `rqrcode`, `chunky_png` and `bigdecimal`.

## Quick start

### Take a payment

```ruby
require 'upi'

generator = Upi::Generator.new(
  upi_id: 'acme@icici',        # your VPA
  name: 'Acme Store',          # shown on the payer's confirmation screen
  merchant_code: '5499'        # your four-digit ISO 18245 category code
)

reference = "ORD#{order.id}"   # unique per payment attempt, see below

png = generator.generate_qr(499.00, 'Order 1042',
                            transaction_ref_id: reference,
                            mode: :png)

File.binwrite('qr.png', png)
```

### Or send a link instead

```ruby
url = generator.upi_content(499.00, 'Order 1042', transaction_ref_id: reference)
# => "upi://pay?pa=acme@icici&pn=Acme%20Store&mc=5499&tr=ORD1042&tn=Order%201042&am=499.00&cu=INR"
```

```erb
<a href="<%= url %>">Pay ₹499</a>
```

On a phone, that link opens the payer's UPI app directly.

### Read what comes back

```ruby
response = Upi::Response.parse(params)

if response.success?
  # A claim by the payer's app, not settlement. Confirm with your PSP
  # before you ship anything.
  Order.find_by(reference: response.transaction_ref).confirm!(response.transaction_id)
end
```

## Concepts worth knowing

Four distinctions explain most of the UPI behaviour people find surprising.

### Static vs dynamic

A **static** QR carries no amount. The payer types one in. This is the code taped to a shop
counter, printed once, scanned forever.

```ruby
generator.upi_content   # => "upi://pay?pa=acme@icici&pn=Acme%20Store&mc=5499&cu=INR"
```

A **dynamic** QR carries an amount, and is generated per transaction.

```ruby
generator.upi_content(499, 'Order 1042', transaction_ref_id: 'ORD1042')
```

Omitting the amount is how you get a static code. Do not pass `0` — UPI apps reject `am=0`, and
this gem raises rather than emit it.

### P2P vs P2M

Passing `merchant_code:` makes it a merchant (P2M) payment, which UPI treats differently:
different limits, different settlement, and stricter validation. Leave it out for
person-to-person transfers.

### The transaction reference is not optional, and not reusable

`tr` is your order or invoice number, echoed back to you when the payment completes. Two rules
matter, and breaking either produces failures that look random:

1. **Merchant payments carrying an amount must have one.** Without it the PSP's risk engine
   sees an amount with nothing to reconcile against and rejects it behind a generic error. This
   gem raises if you forget.
2. **It must be unique per payment attempt.** A repeat is rejected as a duplicate. This is the
   mechanism behind the classic "the QR worked for a week and then stopped" — a fixed reference
   baked into a printed code.

Use your own order id where you have one, or generate a reference:

```ruby
Upi::Generator.generate_reference('ORD')   # => "ORD20260917131656E4BBC91A"
```

### The URI is the payment; QR is just one way to carry it

`upi://pay?...` is the whole payment instruction. A QR code is one transport; an Android
intent, an NFC tap, a BLE broadcast or a link in an email are others. The gem builds the
payload and renders QR codes; moving the bytes over anything else is your application's job.

## Building payments

### Person to person

```ruby
generator = Upi::Generator.new(upi_id: 'ananya@okaxis', name: 'Ananya Rao')

generator.upi_content(250, 'Dinner split')
# => "upi://pay?pa=ananya@okaxis&pn=Ananya%20Rao&tn=Dinner%20split&am=250.00&cu=INR"
```

### Merchant

```ruby
generator = Upi::Generator.new(upi_id: 'acme@icici', name: 'Acme Store', merchant_code: '5499')

generator.upi_content(499, 'Order 1042',
                      transaction_ref_id: 'ORD1042',
                      transaction_id: 'TXN8f3c',
                      url: 'https://acme.example.com/orders/1042')
```

`url` is a "bill in the box" link: the payer can tap through to an invoice or receipt from
inside their UPI app, before authorising. It must be `http` or `https`.

### Let the payer choose, above a floor

`min_amount` maps to the `mam` tag, which makes the amount editable down to a minimum. Useful
for donations and top-ups.

```ruby
generator.upi_content(500, 'Donation', transaction_ref_id: 'DON77', min_amount: 100)
# => "...&tn=Donation&am=500.00&mam=100.00&cu=INR"
```

Without `mam`, the amount is fixed and the payer cannot edit it.

## Rendering QR codes

`generate_qr` takes every payment argument `upi_content` does, plus rendering options.

```ruby
svg = generator.generate_qr(499, 'Order 1042', transaction_ref_id: 'ORD1042')
png = generator.generate_qr(499, 'Order 1042', transaction_ref_id: 'ORD1042', mode: :png)
```

| Option | Default | Notes |
| --- | --- | --- |
| `mode:` | `:svg` | `:svg` returns markup, `:png` returns raw bytes |
| `level:` | `:m` | Error correction: `:l` `:m` `:q` `:h`. Higher survives more damage but packs more modules into the same space |
| anything else | | passed through to [rqrcode](https://github.com/whomwah/rqrcode) |

```ruby
generator.generate_qr(499, 'Order', transaction_ref_id: 'ORD1', mode: :png,
                      module_px_size: 12, border_modules: 2)

generator.generate_qr(499, 'Order', transaction_ref_id: 'ORD1',
                      module_size: 6, color: '1a1a1a')
```

**Size scales with payload, not the other way round.** A longer URI needs more modules, so the
image grows rather than the modules shrinking. Pinning a canvas size instead is how QR codes
become unscannable once the note or URL gets long — if you pass an explicit `size:`, check it
still scans with your longest realistic payload.

A mistyped payment keyword raises rather than being silently swallowed by the renderer:

```ruby
generator.generate_qr(499, 'Order', transaction_ref: 'ORD1')
# ArgumentError: unknown keyword: :transaction_ref. Payment details go to the
# builder's own parameters; svg renderer options are: fill, use_path, offset, ...
```

## Reading the PSP's reply

When the payer's app finishes, it hands your app a response. `Upi::Response` reads it in
whatever shape it arrives.

```ruby
response = Upi::Response.parse(params)                       # a params hash
response = Upi::Response.parse(request.query_string)         # a raw query string
response = Upi::Response.parse('myapp://cb?Status=SUCCESS…') # a full callback URL
response = Upi::Response.parse(Status: 'SUCCESS', txnRef: 'ORD1')
```

| Method | |
| --- | --- |
| `#success?` | the app reported the payment as approved |
| `#failure?` | the app reported it as failed |
| `#submitted?` | in flight; the app could not say either way |
| `#pending?` | submitted, or no status came back at all |
| `#transaction_ref` | the `tr` you sent — how you find your own order |
| `#transaction_id` | the PSP's own id for the transaction |
| `#response_code` | UPI response code; `00` is approved |
| `#approval_ref_no` | beneficiary bank's approval reference |
| `#to_h` | all of the above |

Field names are matched case-insensitively, because apps vary the casing, and both `""` and the
literal string `"null"` become `nil` rather than surviving as strings.

> [!IMPORTANT]
> **A successful response is a claim, not settlement.** The specification is explicit that the
> "merchant app must check the final status with their server/PSP server". Treat `success?` as
> a prompt to confirm server-side, never as authority to release goods. Anything else is how
> payment fraud happens.

## Reading a QR code you received

`Upi::Request` parses in the other direction. Use it to validate a QR before trusting it, or to
work out why someone's code is failing.

```ruby
request = Upi.parse('upi://pay?pa=acme@icici&pn=Acme%20Store&mc=5499&tr=ORD1&am=10.50&cu=INR')

request.payee_address    # => "acme@icici"
request.payee_name       # => "Acme Store"
request.amount           # => BigDecimal("10.5")
request.merchant?        # => true
request.dynamic?         # => true   (carries an amount)
request.signed?          # => false
request.tags             # => the raw tag hash
```

Parsing is deliberately forgiving where generation is strict: a QR in the wild may well have
been built by a tool that got the encoding wrong, and refusing to read it helps nobody. Problems
come back as warnings rather than exceptions, so you can tell a payer *why* their code fails:

```ruby
request = Upi.parse('upi://pay?pa=acme@icici&pn=Acme+Store&am=0&cu=INR&mc=5499')

request.valid?    # => false
request.warnings
# => ["am=0 is rejected by PSP apps; omit the tag to let the payer enter an amount",
#     "tr is mandatory for merchant transactions carrying an amount, and must be unique per attempt",
#     "the URI contains a + where a space was probably meant; spaces must be %20"]
```

**This is the fastest way to debug a failing QR code.** Decode the image with any QR reader,
paste the string in, and read the warnings.

## Recurring payments (UPI AutoPay)

`Upi::Mandate` builds `upi://mandate` URIs — a standing authorisation to debit on a schedule.

```ruby
mandate = Upi::Mandate.new(upi_id: 'acme@icici', name: 'Acme Corp', merchant_code: '7322')

mandate.mandate_content(
  499, 'Pro plan',
  transaction_ref_id: "SUB#{subscription.id}",
  validity_start: Date.today,
  validity_end: Date.today.next_year,
  recurrence: Upi::Mandate::MONTHLY,
  recurrence_type: Upi::Mandate::ON,
  recurrence_value: 1              # debit on the 1st
)
```

`generate_qr` works exactly as it does for payments.

| Option | Values |
| --- | --- |
| `recurrence:` | `ONETIME` `DAILY` `WEEKLY` `FORTNIGHTLY` `MONTHLY` `BIMONTHLY` `QUARTERLY` `HALFYEARLY` `YEARLY` `ASPRESENTED` |
| `recurrence_type:` | `ON` `BEFORE` `AFTER` |
| `recurrence_value:` | which day of the period to debit |
| `amount_rule:` | `MAX` (a ceiling, the default) or `EXACT` |
| `transaction_type:` | `CREATE` `UPDATE` `REVOKE` `PAUSE` `UNPAUSE` |
| `validity_start:` `validity_end:` | a `Date`, or a `DDMMYYYY` string |
| `revocable:` `shareable:` `block_funds:` | `true`/`false`, emitted as `Y`/`N` |
| `mandate_name:` | label shown to the payer |

For usage-based billing where the amount varies, `ASPRESENTED` with `amount_rule: MAX` sets a
ceiling and debits whatever you present against it:

```ruby
mandate.mandate_content(5000, 'Metered usage',
                        transaction_ref_id: 'SUB88',
                        validity_start: Date.today, validity_end: Date.today.next_year,
                        recurrence: Upi::Mandate::ASPRESENTED)
```

To cancel, re-send with the same reference and `transaction_type: REVOKE`.

> [!NOTE]
> **This part is not from the NPCI specification.** That document predates AutoPay and does not
> describe the mandate tags, so this follows the deep links published by PSP aggregators. They
> agree on the core tags but differ at the edges — some expect `block=Y/N`, others `True/False`,
> and the accepted `mode` values vary. Check the exact shape against your own PSP before going
> live. `#tags` shows you precisely what will be emitted:
>
> ```ruby
> mandate.tags(499, 'Pro plan', **options)   # => {pa: "acme@icici", recur: "MONTHLY", …}
> ```

## Signed QR codes and intents

The specification defines a signed variant: the merchant signs the URI with its private key,
and the payer's PSP verifies it against a public key registered with the acquiring bank. This
is what stops someone photographing your QR and reprinting it with their own VPA.

```ruby
signer = Upi::Signer.new(File.read('merchant.pem'))

generator = Upi::Generator.new(
  upi_id: 'acme@icici', name: 'Acme Store', merchant_code: '5499',
  org_id: '000000',          # required when signing
  signer: signer
)

generator.generate_qr(499, 'Order 1042', transaction_ref_id: 'ORD1042',
                      initiation_mode: Upi::Generator::MODE_SECURE_QR)
```

SHA-256 with RSA, base64-encoded, appended as `sign` — which is emitted last, as the
specification requires, and covers everything before it. Mandates can be signed the same way.

> [!WARNING]
> Signing is entirely local; nothing here talks to NPCI. **The operational half is not:** your
> keypair must be registered with your acquiring bank before any PSP will accept the signature.
> Until then a signed QR is no better than an unsigned one, and possibly worse.

Signature *verification* is deliberately not offered. That is the payer PSP's job, done against
a daily-refreshed cache of registered merchant keys; a merchant-side gem cannot do it
meaningfully. `Signer#verify` exists only for round-tripping in your own tests.

## Transports beyond QR

The same URI can travel over anything. Only the `mode` tag records which route it took.

| Constant | Value | |
| --- | --- | --- |
| `MODE_DEFAULT` | `00` | unspecified |
| `MODE_QR` | `01` | QR code |
| `MODE_SECURE_QR` | `02` | signed QR |
| `MODE_INTENT` | `04` | Android intent |
| `MODE_SECURE_INTENT` | `05` | signed intent |
| `MODE_NFC` | `06` | NFC tap |
| `MODE_BLE` | `07` | Bluetooth |
| `MODE_UHF` | `08` | ultra high frequency |
| `MODE_SEBI` | `15` | SEBI flows |

```ruby
generator.upi_content(499, 'Order', transaction_ref_id: 'ORD1',
                      initiation_mode: Upi::Generator::MODE_INTENT)
```

The tag is omitted unless you ask for it, since most PSP apps accept a URI without one and
existing integrations rely on that.

## Recipes

### Rails: a checkout QR

```ruby
# config/initializers/upi.rb — generators are immutable and thread safe,
# so build one once and share it.
UPI_MERCHANT = Upi::Generator.new(
  upi_id: Rails.application.credentials.dig(:upi, :vpa),
  name: 'Acme Store',
  merchant_code: '5499'
).freeze
```

```ruby
class CheckoutsController < ApplicationController
  def show
    @order = Order.find(params[:id])

    send_data UPI_MERCHANT.generate_qr(
      @order.total,                       # a BigDecimal from a decimal column
      "Order #{@order.number}",
      transaction_ref_id: @order.payment_reference,
      url: order_receipt_url(@order),
      mode: :png
    ), type: 'image/png', disposition: 'inline'
  end
end
```

Give each order a stable, unique reference once and store it, so a retried render produces the
same QR while a *new* attempt gets a fresh one:

```ruby
class Order < ApplicationRecord
  before_create { self.payment_reference ||= Upi::Generator.generate_reference('ORD') }
end
```

### Inline in a page, no controller round trip

```ruby
svg = UPI_MERCHANT.generate_qr(order.total, "Order #{order.number}",
                               transaction_ref_id: order.payment_reference)
```

```erb
<div class="qr"><%= raw svg %></div>
```

SVG stays sharp at any size and avoids a second request. For email, use PNG — most clients will
not render inline SVG.

### A printed QR for the shop counter

Static, no amount, no reference. Printed once and reused indefinitely; the payer types the
amount.

```ruby
counter = Upi::Generator.new(upi_id: 'acme@icici', name: 'Acme Store', merchant_code: '5499')

File.binwrite('counter.png', counter.generate_qr(mode: :png, module_px_size: 16, level: :h))
```

Use `level: :h` for anything printed — it survives smudges, creases and bad lighting.

> [!CAUTION]
> Never print a QR that carries a fixed `tr`. It will work once and then be rejected as a
> duplicate on every later scan. Printed codes must be static.

### A subscription

```ruby
MANDATE = Upi::Mandate.new(upi_id: 'acme@icici', name: 'Acme Corp', merchant_code: '7322')

MANDATE.generate_qr(
  plan.price, plan.name,
  transaction_ref_id: subscription.reference,
  validity_start: subscription.starts_on,
  validity_end: subscription.ends_on,
  recurrence: Upi::Mandate::MONTHLY,
  recurrence_type: Upi::Mandate::ON,
  recurrence_value: subscription.starts_on.day,
  mandate_name: "#{plan.name} subscription",
  revocable: true,
  mode: :png
)
```

### Handling the callback

```ruby
class UpiCallbacksController < ApplicationController
  def create
    response = Upi::Response.parse(params.to_unsafe_h)
    order = Order.find_by!(payment_reference: response.transaction_ref)

    if response.pending?
      order.mark_pending!
    elsif response.success?
      # Do not fulfil here. Confirm with the PSP first.
      ConfirmPaymentJob.perform_later(order, response.transaction_id)
    else
      order.mark_failed!(response.response_code)
    end

    head :ok
  end
end
```

### Debugging a QR that customers say does not work

```ruby
request = Upi.parse(decoded_qr_contents)

puts request.valid? ? 'looks payable' : request.warnings
```

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| "Limit exceeded" on a small amount | Generic PSP error for a malformed payload — usually a missing `tr` on a merchant payment | Pass `transaction_ref_id:`. The gem raises if you forget |
| Worked for a while, now always fails | A reused `tr`, rejected as a duplicate | One reference per attempt; `generate_reference` |
| Fails for some amounts, works for others | Float precision, or more than two decimals | Pass a `String` or `BigDecimal` |
| App says the amount is invalid | `am=0` | Omit the amount entirely for a payer-entered one |
| Payee name shows as `Acme+Store` | `+` used for spaces instead of `%20` | Fixed in 3.0; check you are not building URIs by hand elsewhere |
| Parameters vanish after the note | An unescaped `&` or `#` in the note | Fixed in 3.0 |
| QR will not scan reliably | Modules too small for the payload | Raise `module_px_size:`, or drop a fixed `size:`; shorten the note and URL |
| Scans, but nothing happens on desktop | `upi://` needs a UPI app; desktop browsers have none | Show a QR on desktop, a link on mobile |
| `ValidationError` on a real VPA | Unusual characters in the address | Open an issue with the VPA shape — the pattern is deliberately conservative |

Two rules cover most of the rest: **unique reference per attempt**, and **never let a float
near an amount**.

## API reference

### `Upi::Generator`

```ruby
Upi::Generator.new(upi_id:, name:, currency: 'INR', merchant_code: nil,
                   org_id: nil, signer: nil, no_url_parse: true)
```

| | |
| --- | --- |
| `upi_id:` | **required.** Payee VPA, `name@psp`. Max 255 characters |
| `name:` | **required.** Payee name, max 99 characters |
| `currency:` | `'INR'` only, the sole value UPI supports |
| `merchant_code:` | four-digit ISO 18245 code; its presence selects merchant mode |
| `org_id:` | six-digit `orgid`, required when signing |
| `signer:` | a `Upi::Signer` |
| `no_url_parse:` | encoding strictness, see [Encoding](#encoding) |

```ruby
#upi_content(amount = nil, note = nil, transaction_ref_id:, transaction_id:,
             url:, min_amount:, initiation_mode:) -> String
#generate_qr(…same…, mode: :svg, level: :m, **renderer) -> String
.generate_reference(prefix = 'UPI') -> String
#params -> Hash   # frozen constructor tags
```

| Payment argument | Tag | Notes |
| --- | --- | --- |
| `amount` | `am` | first positional; omit for a payer-entered amount |
| `note` | `tn` | second positional; max 50 characters |
| `transaction_ref_id:` | `tr` | max 35 alphanumeric; required for merchant + amount |
| `transaction_id:` | `tid` | max 35 alphanumeric; PSP-generated where present |
| `url:` | `url` | `http(s)` link to a bill or receipt |
| `min_amount:` | `mam` | makes the amount editable down to this floor |
| `initiation_mode:` | `mode` | see [Transports](#transports-beyond-qr) |

### `Upi::Mandate`

Same constructor. `#mandate_content` and `#generate_qr` take the amount and note positionally
plus the mandate keywords listed under [Recurring payments](#recurring-payments-upi-autopay);
`#tags` returns what would be emitted, in order.

### `Upi::Request`

```ruby
Upi::Request.parse(uri, plus_as_space: true) -> Request    # also Upi.parse
```

Readers: `#payee_address` `#payee_name` `#merchant_code` `#transaction_id` `#transaction_ref`
`#note` `#amount` `#min_amount` `#currency` `#url` `#initiation_mode` `#org_id` `#signature`
`#tags` `#to_h`.
Predicates: `#pay?` `#mandate?` `#merchant?` `#dynamic?` `#signed?` `#valid?`.
Diagnostics: `#warnings`.

`plus_as_space` defaults to `true` because QR codes built with form encoding are common,
including ones this gem produced before 3.0. Set it to `false` to treat `+` literally.

### `Upi::Response`

```ruby
Upi::Response.parse(input = nil, plus_as_space: true, **fields) -> Response  # also Upi.parse_response
```

Accepts a query string, a callback URL, a hash, or loose keywords.

### `Upi::Signer`

```ruby
Upi::Signer.new(key, passphrase: nil)   # OpenSSL::PKey::RSA, or PEM/DER text
#sign(content) -> String                # base64
#verify(content, signature) -> Boolean  # for your tests, not for PSP verification
```

Rejects public keys and keys under 2048 bits.

### Errors

`Upi::Error` is the base. `Upi::ValidationError` means the details cannot produce a valid URI;
`Upi::ParseError` means something could not be read. Both inherit from `Upi::Error`, so rescuing
that catches everything the gem raises.

## Amounts and money

Amounts are normalised to the two-decimal format UPI requires, and anything that cannot be
represented that way raises rather than silently becoming a different number.

```ruby
generator.upi_content(100)                  # am=100.00
generator.upi_content(1499.5)               # am=1499.50
generator.upi_content(0.1 + 0.2)            # am=0.30      float noise discarded
generator.upi_content(BigDecimal('99.9'))   # am=99.90
generator.upi_content('249.50')             # am=249.50

generator.upi_content(100.456)              # raises: more than two decimal places
generator.upi_content(0)                    # raises: UPI apps reject am=0
generator.upi_content(-5)                   # raises
```

Floats are converted through `BigDecimal` at 15 significant digits, which discards IEEE
representation noise while preserving precision you actually meant — so `0.1 + 0.2` is accepted
as `0.30`, but `100.456` still raises instead of being quietly rounded to `100.46`.

**Prefer `String` or `BigDecimal`.** If the amount comes from a decimal column it already is
one; keep it that way and no float ever touches your money.

## Specification coverage

Built against the NPCI UPI Linking Specification v1.6.

| Tag | Supported | |
| --- | :-: | --- |
| `pa` `pn` `mc` `tid` `tr` `tn` `am` `mam` `cu` `url` | ✅ | full payment payload |
| `mode` | ✅ | opt-in, all nine values |
| `orgid` `sign` | ✅ | signed QR and intent |
| `mid` `msid` `mtid` | ❌ | merchant reconciliation tags, not yet implemented |
| mandate tags | ✅ | from PSP aggregator docs, not the NPCI spec |
| response fields | ✅ | `txnId` `responseCode` `ApprovalRefNo` `Status` `txnRef` |

Deliberately out of scope: signature *verification*, and anything that talks to the UPI switch.
Both are PSP and bank territory, requiring credentials and a network position a client gem has
no business holding.

### Validation

Every field is checked before a URI is built, and a failure raises `Upi::ValidationError`.
This is deliberate: an invalid URI still produces a scannable QR code, so without validation the
only symptom is a payment that fails later, in someone else's app.

```ruby
Upi::Generator.new(upi_id: 'not-a-vpa', name: 'X')
# Upi::ValidationError: upi_id "not-a-vpa" is not a valid UPI address (expected 'name@psp')
```

### Encoding

Values are percent-encoded per RFC 3986 §2.1, with spaces as `%20`, which the specification
requires explicitly. `no_url_parse` chooses how aggressive that is:

- `true` (default) encodes down to the unreserved set.
- `false` leaves URL-safe punctuation such as `:` and `/` readable.

Either way `&`, `#`, `%`, `+` and space are always escaped, so a note like `Tea & Coffee #12`
can never truncate the URI or forge a parameter. Redirect URLs keep a readable `://` in both
modes.

## Compatibility

| | |
| --- | --- |
| Ruby | 2.6+ — tested on 2.7, 3.1 and 3.3 |
| Thread safety | builders are immutable; share one instance freely |
| Dependencies | `rqrcode` `chunky_png` `bigdecimal` |

## Upgrading

3.1 is purely additive: everything new lives in classes that did not exist before, existing
`Upi::Generator` behaviour is unchanged, and `require 'upi'` still loads everything.

### From 2.x

3.0 changed the generated URI so that it complies with the specification. Any test asserting an
exact `upi://` string needs updating:

- spaces encode as `%20`, not `+`, and tags follow the specification's order
- amounts always carry two decimals: `am=100` is now `am=100.00`
- calling without an amount no longer emits `am=0&tn=`; both tags are omitted
- invalid input raises `Upi::ValidationError`; merchant payments with an amount now require
  `transaction_ref_id`
- `#params` returns the frozen constructor tags, not the last call's state
- PNG dimensions vary with payload; pass `size:` or `module_px_size:` to control it

Full detail in the [CHANGELOG](CHANGELOG.md).

## Development

```console
$ bin/setup                 # install dependencies
$ bundle exec rake          # specs and RuboCop, what CI runs
$ bundle exec rspec spec/upi/request_spec.rb:42
$ bin/console               # IRB with the gem loaded
```

To release: bump `Upi::VERSION`, add a `CHANGELOG.md` entry, then `bundle exec rake release`.
Build and install the packaged gem into a clean `GEM_HOME` first — the gemspec takes its file
list from `git ls-files`, so anything untracked is silently missing from the package.

## Contributing

Bug reports and pull requests are welcome at https://github.com/stingrayzboy/upi.

Especially welcome: VPA formats this gem rejects but a real PSP accepts, and mandate tag shapes
that differ from what your PSP expects. Both are places where the implementation is necessarily
conservative and real-world reports are the only way to improve it.

Contributors are expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

## License

[MIT](https://opensource.org/licenses/MIT).
