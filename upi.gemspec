# frozen_string_literal: true

require_relative "lib/upi/version"

Gem::Specification.new do |spec|
  spec.name = "upi"
  spec.version = Upi::VERSION
  spec.authors = ["Faraz Noor"]
  spec.email = ["faraznoor75@gmail.com"]

  spec.summary = "Generate UPI codes for payments."
  spec.description = "This gem generates UPI QR codes for payments. It can be used in e-commerce applications to generate QR codes for payments. The QR codes can be scanned by UPI apps to make payments. The gem uses the rqrcode gem to generate the QR codes."
  spec.homepage = "https://github.com/stingrayzboy/upi"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = "https://github.com/stingrayzboy/upi"
  spec.metadata["source_code_uri"] = "https://github.com/stingrayzboy/upi"
  spec.metadata["changelog_uri"] = "https://github.com/stingrayzboy/upi/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_runtime_dependency 'rqrcode', '~> 1.1'
  spec.add_runtime_dependency 'chunky_png'
  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
