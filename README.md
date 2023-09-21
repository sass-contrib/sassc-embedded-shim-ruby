# Embedded Sass Shim for SassC Ruby

[![build](https://github.com/ntkme/sassc-embedded-shim-ruby/actions/workflows/build.yml/badge.svg)](https://github.com/ntkme/sassc-embedded-shim-ruby/actions/workflows/build.yml)
[![gem](https://badge.fury.io/rb/sassc-embedded.svg)](https://rubygems.org/gems/sassc-embedded)

Use `sass-embedded` with SassC Ruby!

This library shims [`sassc`](https://github.com/sass/sassc-ruby) with the [`sass-embedded`](https://github.com/ntkme/sass-embedded-host-ruby) implementation.

It has been tested with:

- [`sassc`](https://github.com/sass/sassc-ruby)
- [`sassc-rails`](https://github.com/sass/sassc-rails)
- [`sprockets`](https://github.com/rails/sprockets)
- [`sprockets-rails`](https://github.com/rails/sprockets-rails)

## Install

Add these lines to your application's Gemfile:

``` ruby
gem 'sassc', github: 'sass/sassc-ruby', ref: 'refs/pull/233/head' # recommended, see comment below
gem 'sassc-embedded'

# The fork of `sassc` at https://github.com/sass/sassc-ruby/pull/233 removes the libsass extension
# and loads the shim automatically when `require 'sassc'` is invoked, meaning no code changes needed.
# ---
# Alternatively, the shim can be loaded explictly with `require 'sassc-embedded'` in your application.
```

And then execute:

``` sh
bundle
```

Or install it yourself as:

``` sh
gem install sassc-embedded
```

## Usage

This shim utilizes `sass-embedded` to allow you to compile SCSS or SASS syntax to CSS. To compile, use a `SassC::Engine`, e.g.:

``` ruby
require 'sassc-embedded'

SassC::Engine.new(sass, style: :compressed).render
```

See [rubydoc.info/gems/sassc](https://rubydoc.info/gems/sassc) for full API documentation.

## Behavioral Differences from SassC Ruby

1. Option `:style => :nested` and `:style => :compact` behave as `:style => :expanded`.

2. Option `:precision` is ignored.

3. Option `:line_comments` is ignored.

See [the dart-sass documentation](https://github.com/sass/dart-sass#behavioral-differences-from-ruby-sass) for other differences.
