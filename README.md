# Embedded Sass Shim for SassC Ruby

[![build](https://github.com/sass-contrib/sassc-embedded-shim-ruby/actions/workflows/build.yml/badge.svg)](https://github.com/sass-contrib/sassc-embedded-shim-ruby/actions/workflows/build.yml)
[![gem](https://badge.fury.io/rb/sassc-embedded.svg)](https://rubygems.org/gems/sassc-embedded)

Use `sass-embedded` with SassC Ruby!

This library shims [`sassc`](https://github.com/sass/sassc-ruby) with the [`sass-embedded`](https://github.com/sass-contrib/sass-embedded-host-ruby) implementation.

## Which Sass implementation should I use for my Ruby project?

- [`sass-embedded`](https://github.com/sass-contrib/sass-embedded-host-ruby) is recommended for all projects. It is compatible with:
  - [`dartsass-rails >=0.5.0`](https://github.com/rails/dartsass-rails)
  - [`haml >=6.0.9`](https://github.com/haml/haml)
  - [`silm >=5.2.0`](https://github.com/slim-template/slim)
  - [`sinatra >=3.1.0`](https://github.com/sinatra/sinatra)
  - [`tilt >=2.0.11`](https://github.com/jeremyevans/tilt)
- [`sassc-embedded`](https://github.com/sass-contrib/sassc-embedded-shim-ruby) is recommended for existing projects still using `sassc` or `sprockets`. It is compatible with:
  - [`dartsass-sprockets`](https://github.com/tablecheck/dartsass-sprockets)
  - [`sassc`](https://github.com/sass/sassc-ruby)
  - [`sassc-rails`](https://github.com/sass/sassc-rails)
  - [`sprockets`](https://github.com/rails/sprockets)
  - [`sprockets-rails`](https://github.com/rails/sprockets-rails)
- [`sassc`](https://github.com/sass/sassc-ruby) [is deprecated](https://sass-lang.com/blog/libsass-is-deprecated/).
- [`sass`](https://github.com/sass/ruby-sass) [has reached end-of-life](https://sass-lang.com/blog/ruby-sass-is-unsupported/).

## Install

Add this line to your application's Gemfile:

``` ruby
gem 'sassc-embedded'
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

## Troubleshooting

### The original `sassc` gem is still being used instead of `sassc-embedded`

When launching an application via `bundle exec`, it puts `sassc-embedded` at higher priority than `sassc` in `$LOAD_PATH`. You can verify the order of `$LOAD_PATH` with the following command:

``` ruby
bundle exec ruby -e 'puts $LOAD_PATH'
```

If you see `sassc` has higher priority than `sassc-embedded`, try remove `sassc`:

```
bundle remove sassc
```

If your application has a transitive dependency on `sassc` that cannot be removed, you can use one of the following workarounds.

#### Workaround One

Add this line to your application's Gemfile:

``` ruby
gem 'sassc', github: 'sass/sassc-ruby', ref: 'refs/pull/233/head'
```

And then execute:

``` sh
bundle
```

The fork of `sassc` at https://github.com/sass/sassc-ruby/pull/233 will load the shim whenever `require 'sassc'` is invoked, meaning no other code changes needed in your application.

#### Workaround Two

Add this line to your application's code:

``` ruby
require 'sassc-embedded'
```
