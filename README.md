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

This polyfill utilizes `sass-embedded` to allow you to compile SCSS or SASS syntax to CSS. To compile, use a `SassC::Engine`, e.g.:

``` ruby
require 'sassc-embedded'

SassC::Engine.new(sass, style: :compressed).render
```

See [rubydoc.info/gems/sassc](https://rubydoc.info/gems/sassc) for full API documentation.

## Behavioral Differences from SassC Ruby

1. Option `:style => :nested` behaves as `:expanded`.
2. Option `:style => :compact` behaves as `:compressed`.
3. Option `:precision` is ignored.
4. Option `:line_comments` is ignored.
5. In `Importer#imports(path, parent_path)`, argument `path` is set to absolute path, and argument `parent_path` is set to value of option `:filename`.
6. See [the dart-sass documentation](https://github.com/sass/dart-sass#behavioral-differences-from-ruby-sass) for other differences.
