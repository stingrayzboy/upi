## [Unreleased]
- In the making

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
