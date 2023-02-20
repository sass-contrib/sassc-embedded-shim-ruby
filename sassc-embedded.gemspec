# frozen_string_literal: true

require_relative 'lib/sassc/embedded/version'

Gem::Specification.new do |spec| # rubocop:disable Gemspec/RequireMFA
  spec.name          = 'sassc-embedded'
  spec.version       = SassC::Embedded::VERSION
  spec.authors       = ['なつき']
  spec.email         = ['i@ntk.me']
  spec.summary       = 'Use dart-sass with SassC!'
  spec.description   = 'An embedded sass shim for SassC.'
  spec.homepage      = 'https://github.com/ntkme/sassc-embedded-shim-ruby'
  spec.license       = 'MIT'
  spec.metadata      = {
    'documentation_uri' => "https://rubydoc.info/gems/#{spec.name}/#{spec.version}",
    'source_code_uri' => "#{spec.homepage}/tree/v#{spec.version}",
    'funding_uri' => 'https://github.com/sponsors/ntkme'
  }

  spec.files = Dir['lib/**/*.rb'] + [
    'LICENSE',
    'README.md'
  ]

  spec.required_ruby_version = '>= 2.6.0'

  spec.add_runtime_dependency 'sassc', '~> 2.0'
  spec.add_runtime_dependency 'sass-embedded', '~> 1.54'

  spec.add_development_dependency 'minitest', '~> 5.17.0'
  spec.add_development_dependency 'minitest-around', '~> 0.5.0'
  spec.add_development_dependency 'rake', '>= 10.0.0'
  spec.add_development_dependency 'rubocop', '~> 1.45.0'
  spec.add_development_dependency 'rubocop-minitest', '~> 0.28.0'
  spec.add_development_dependency 'rubocop-performance', '~> 1.16.0'
  spec.add_development_dependency 'rubocop-rake', '~> 0.6.0'
end
