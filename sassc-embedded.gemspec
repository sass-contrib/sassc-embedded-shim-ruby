# frozen_string_literal: true

require_relative 'lib/sassc/embedded/version'

Gem::Specification.new do |spec| # rubocop:disable Gemspec/RequireMFA
  spec.name          = 'sassc-embedded'
  spec.version       = SassC::Embedded::VERSION
  spec.authors       = ['なつき']
  spec.email         = ['i@ntk.me']
  spec.summary       = 'Use dart-sass with SassC!'
  spec.description   = 'An embedded sass shim for SassC.'
  spec.homepage      = 'https://github.com/sass-contrib/sassc-embedded-shim-ruby'
  spec.license       = 'MIT'
  spec.metadata      = {
    'documentation_uri' => 'https://rubydoc.info/gems/sassc',
    'source_code_uri' => "#{spec.homepage}/tree/v#{spec.version}",
    'funding_uri' => 'https://github.com/sponsors/ntkme'
  }

  spec.files = Dir['lib/**/*.rb', 'vendor/github.com/sass/sassc-ruby/lib/**/*.rb'] + [
    'LICENSE',
    'README.md',
    'vendor/github.com/sass/sassc-ruby/LICENSE.txt'
  ]

  spec.require_paths = ['lib', 'vendor/github.com/sass/sassc-ruby/lib']

  spec.required_ruby_version = '>= 3.1.0'

  spec.add_runtime_dependency 'sass-embedded', '~> 1.69'
end
