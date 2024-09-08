## [Unreleased]
- In the making

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
