## [Unreleased]
- In the making

## [3.1.0] - 2026-09-17

Completes the round trip. 3.0.0 could build a correct payment URI; this release
can also read one back, read the PSP's reply, sign what it builds, and set up
recurring payments.

### Added
- `Upi::Response` parses the reply a PSP app hands back to the merchant app
  (`txnId`, `responseCode`, `ApprovalRefNo`, `Status`, `txnRef`), per section 1.4
  of the specification. Accepts a query string, a full callback URL, or a params
  hash; matches field names case-insensitively, since apps vary the casing; and
  turns `""` and the literal string `"null"` into `nil`. `#success?`,
  `#failure?`, `#pending?`. The specification is clear that this is a hint and
  not settlement, so confirm server-side before releasing goods.
- `Upi::Signer` signs intents and QR codes per section 1.3: SHA-256 with RSA,
  base64, appended as `sign`, which is emitted last as the specification
  requires. Pass `signer:` and `org_id:` to `Upi::Generator` or `Upi::Mandate`.
  Signing is local; registering the keypair with your acquiring bank is not, and
  remains your job. Verification is deliberately not offered: that is the payer
  PSP's role.
- `Upi::Request` reads a `upi://` URI back apart, for checking a QR code you
  received rather than one you built. Parsing is forgiving where generation is
  strict, reporting problems through `#warnings` and `#valid?` rather than
  raising, so you can tell a payer why their code will not work. It decodes `+`
  as a space by default, which includes QR codes this gem itself produced before
  3.0.0.
- `Upi::Mandate` builds `upi://mandate` URIs for UPI AutoPay, covering the
  validity window, recurrence, amount rule, revocability, fund blocking and
  mandate lifecycle (`CREATE`, `UPDATE`, `REVOKE`, `PAUSE`, `UNPAUSE`). Modelled
  on PSP aggregator documentation rather than the NPCI Linking Specification,
  which predates AutoPay; check the exact tags against your PSP with `#tags`.
- Initiation modes for every transport the specification lists: `MODE_INTENT`,
  `MODE_SECURE_INTENT`, `MODE_NFC`, `MODE_BLE`, `MODE_UHF` and `MODE_SEBI`, plus
  `SECURE_MODES`. The URI is transport agnostic; only this tag says which route
  it took.
- `Upi.parse` and `Upi.parse_response` as shorthands.

### Fixed
- `#generate_qr` validates its renderer arguments before building the payload,
  so a mistyped payment keyword names itself instead of surfacing as whatever
  missing-field error the typo happens to cause.

### Changed
- The gem is now several files under `lib/upi/` rather than one. `require 'upi'`
  is unchanged.
- The README is rewritten: quick start, concepts, recipes, a troubleshooting
  table mapping symptoms to causes, and a full API reference.
- `bigdecimal` is declared as a runtime dependency, since it became a bundled
  gem in Ruby 3.4. The `base64` stdlib is no longer required at all.

## [3.0.0] - 2026-09-17

Correctness release. Earlier versions could emit a UPI URI that violated the NPCI
UPI Linking Specification. The QR code still scanned, so the only symptom was a
payment that failed in the payer's app, seemingly at random, depending on the
amount and note involved.

### Fixed
- Spaces are now percent-encoded as `%20` instead of `+`. The specification's own
  example URIs use `%20`; `+` is only correct for HTML form bodies, and PSP apps
  that decode strictly showed names like `Test+User`.
- Amounts are normalised to exactly two decimal places. `1499.5` now emits
  `am=1499.50`, and float representation noise (`0.1 + 0.2`) no longer emits
  `am=0.30000000000000004`, which PSP apps reject.
- An amount with more than two decimal places, a zero amount, or a negative amount
  now raises `Upi::ValidationError` instead of producing an unpayable QR code.
- `am` and `tn` are omitted entirely when not supplied. Previously every call
  without an amount emitted `am=0&tn=`, which Google Pay and PhonePe reject.
- Values can no longer break out of the query string. A note containing `&` or `#`
  used to truncate or forge parameters in `no_url_parse: false` mode.
- PNG output is sized by module rather than pinned to a 300px canvas, so a longer
  payload produces a larger image instead of modules too small to scan reliably.
- `#upi_content` and `#generate_qr` no longer mutate the instance. `#params` is
  frozen, calls no longer leak into one another, and instances can be shared.

### Added
- Validation of every field against the specification: payee address format,
  four-digit ISO 18245 merchant code, `INR`-only currency, 50-character note
  limit, 35-character alphanumeric references, and `http(s)`-only URLs.
- `transaction_ref_id` is now required for merchant transactions carrying an
  amount, as the specification mandates, and `Upi::Generator.generate_reference`
  builds a unique one. A reused reference is rejected by PSPs as a duplicate,
  which is why a QR with a hard-coded reference works once and then stops.
- `min_amount:` for the `mam` tag, which lets the payer edit the amount down to a
  floor.
- `initiation_mode:` for the `mode` tag, with `MODE_QR` and friends. Opt-in.
- `level:` and renderer options on `#generate_qr`.
- `Upi::ValidationError`.

### Changed
- Parameters are emitted in the order used by the specification's examples:
  `pa, pn, mc, tid, tr, tn, am, mam, cu, url, mode`.
- `no_url_parse: false` now means "leave URL-safe punctuation readable" rather
  than "do not escape anything"; separators are always escaped in both modes.
- `#params` returns the frozen constructor parameters, not the last call's state.
- QR error correction defaults to `:m` rather than rqrcode's `:h`, giving larger
  modules at the same image size.

## [2.0.2] - 2024-09-08
- For Individual Mode there need not be merchant code being sent. Removed default '0000'. Can be still added explicitly.
- Changed the upi_content method to not parse the upi address and keep it as it is.
- Add support for no uri parse.

## [2.0.1] - 2024-09-06
- Updated Dependencies

## [2.0.0] - 2024-09-06
- Add support for changing amounts after initialization
- Make Merchant Code default 0000 for individual users

## [1.0.2] - 2024-09-05
- Fixed `generate_qr` method to return the QR code as a string instead of writing it to a file.
- Updated README with new usage instructions.

## [1.0.1] - 2024-09-05
- Linting Fixes

## [1.0.0] - 2024-09-05

- Added `mode` option to `generate_qr` method to support both PNG and SVG formats.
- Made `upi_content` method public for easier access.
- Improved handling of QR code generation and added detailed error handling.

## [0.1.0] - 2024-09-05

- Initial release
