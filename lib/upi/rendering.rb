# frozen_string_literal: true

require 'rqrcode'
require 'chunky_png'

module Upi
  # QR rendering shared by the payment and mandate builders.
  module Rendering
    # Renderer options accepted by rqrcode, used to reject a mistyped payment
    # keyword rather than let it fall through to the renderer and quietly drop a
    # field from the QR code.
    SVG_OPTIONS = %i[fill use_path offset color shape_rendering module_size standalone
                     viewbox svg_attributes].freeze
    PNG_OPTIONS = %i[bit_depth border_modules color_mode color file fill module_px_size
                     resize_exactly_to resize_gte_to size].freeze

    SVG_DEFAULTS = { color: '000', shape_rendering: 'crispEdges', module_size: 11 }.freeze

    # Sizing is driven by module size rather than a fixed canvas: a longer
    # payload needs more modules, and pinning the canvas shrinks each module
    # until scanners start to struggle.
    PNG_DEFAULTS = {
      bit_depth: 1,
      border_modules: 4,
      color: 'black',
      file: nil,
      fill: 'white',
      module_px_size: 8,
      resize_exactly_to: false,
      resize_gte_to: false
    }.freeze

    private

    # Checked before the payload is built, so a mistyped payment keyword names
    # itself instead of surfacing later as a missing-field error.
    def check_render!(mode, options)
      raise ArgumentError, "Unsupported mode: #{mode}. Use :svg or :png." unless %i[svg png].include?(mode)

      validate_render_options!(options, mode)
    end

    def render(content, mode, level, options)
      check_render!(mode, options)
      qrcode = RQRCode::QRCode.new(content, level: level)

      if mode == :svg
        qrcode.as_svg(SVG_DEFAULTS.merge(options))
      else
        qrcode.as_png(**PNG_DEFAULTS.merge(color_mode: ChunkyPNG::COLOR_GRAYSCALE).merge(options)).to_s
      end
    end

    def validate_render_options!(options, mode)
      allowed = mode == :svg ? SVG_OPTIONS : PNG_OPTIONS
      unknown = options.keys - allowed
      return if unknown.empty?

      raise ArgumentError,
            "unknown keyword#{"s" if unknown.size > 1}: #{unknown.map(&:inspect).join(", ")}. " \
            "Payment details go to the builder's own parameters; " \
            "#{mode} renderer options are: #{allowed.join(", ")}."
    end
  end
end
