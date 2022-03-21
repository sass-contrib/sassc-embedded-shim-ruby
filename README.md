# Embedded Sass Polyfill for SassC Ruby

[![build](https://github.com/ntkme/sassc-embedded-polyfill-ruby/actions/workflows/build.yml/badge.svg)](https://github.com/ntkme/sassc-embedded-polyfill-ruby/actions/workflows/build.yml)
[![gem](https://badge.fury.io/rb/sassc-embedded.svg)](https://rubygems.org/gems/sassc-embedded)

Use `sass-embedded` with SassC Ruby!

This library polyfills [`sassc`](https://github.com/sass/sassc-ruby) with the [`sass-embedded`](https://github.com/ntkme/sass-embedded-host-ruby) implementation.


## Install

``` sh
gem install sassc-embedded
```

## Usage

To compile, `require 'sassc/embedded'` before use a `SassC::Engine`, e.g.:

``` ruby
require 'sassc/embedded'

SassC::Engine.new(sass, style: :compressed).render
```

See [rubydoc.info/gems/sassc](https://rubydoc.info/gems/sassc) for full API documentation.

## Behavioral Differences from SassC Ruby

1. Option `:style => :nested` behaves as `:expanded`.
2. Option `:style => :compact` behaves as `:compressed`.
3. Option `:precision` is ignored.
4. Option `:line_comments` is ignored.
5. Argument `parent_path` in `Importer#imports` is set to value of option `:filename`.