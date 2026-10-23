# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

module SassC
  class ModernFunctionsTest < Minitest::Test
    include FixtureHelper

    def setup
      @real_stderr = $stderr
      $stderr = StringIO.new
    end

    def teardown
      $stderr = @real_stderr
    end

    def test_function_that_returns_a_rgba_color
      assert_sass <<-SCSS, <<-CSS
        div { background: returns-a-rgba-color(); }
      SCSS
        div { background: black; }
      CSS
    end

    def test_function_that_returns_a_hsla_color
      assert_sass <<-SCSS, <<-CSS
        div { background: returns-a-hsla-color(); }
      SCSS
        div { background: hsl(0, 0%, 0%); }
      CSS
    end

    def test_function_that_returns_a_hwba_color
      assert_sass <<-SCSS, <<-CSS
        div { background: returns-a-hwba-color(); }
      SCSS
        div { background: red; }
      CSS
    end

    def test_function_that_returns_a_sass_calculation
      assert_sass <<-SCSS, <<-CSS
        $my-calc: returns-sass-calculation();
        div { width: $my-calc; }
      SCSS
        div { width: calc(10px + 5%); }
      CSS
    end

    def test_function_that_takes_a_sass_calculation
      assert_sass <<-SCSS, <<-CSS
        div { width: inspect-calculation(calc(10px + 5%)); }
      SCSS
        div { width: calc(10px + 5%); }
      CSS
    end

    def test_function_that_returns_a_sass_function
      assert_sass <<-SCSS, <<-CSS
        @use 'sass:meta';
        $my-func: returns-sass-function();
        div { width: meta.call($my-func, 2); }
      SCSS
        div { width: 3; }
      CSS
    end

    def test_function_that_takes_a_sass_function
      assert_sass <<-SCSS, <<-CSS
        @use 'sass:meta';
        @function plusOne($n) {@return $n + 1}
        div { width: meta.call(inspect-function(meta.get-function('plusOne')), 2); }
      SCSS
        div { width: 3; }
      CSS
    end

    private

    def assert_sass(sass, expected_css)
      engine = Engine.new(sass)

      assert_equal expected_css.strip.gsub!(/\s+/, ' '), # poor man's String#squish
                   engine.render.strip.gsub!(/\s+/, ' ')
    end

    def stderr_output
      $stderr.string.gsub("\u0000\n", '').chomp
    end

    module Script::Functions # rubocop:disable Style/ClassAndModuleChildren
      def returns_a_rgba_color
        SassC::Script::Value::Color.new(red: 0, green: 0, blue: 0, space: 'rgb')
      end

      def returns_a_hsla_color
        SassC::Script::Value::Color.new(hue: 0, saturation: 0, lightness: 0, space: 'hsl')
      end

      def returns_a_hwba_color
        SassC::Script::Value::Color.new(hue: 0, whiteness: 0, blackness: 0, space: 'hwb')
      end

      def inspect_calculation(argument)
        unless argument.is_a? SassC::Script::Value::Calculation
          raise StandardError, 'passed value is not a Sass::Script::Value::Calculation'
        end

        argument
      end

      def inspect_function(argument)
        unless argument.is_a? SassC::Script::Value::Function
          raise StandardError, 'passed value is not a Sass::Script::Value::Function'
        end

        argument
      end

      def returns_sass_calculation
        SassC::Script::Value::Calculation.calc(
          SassC::Script::CalculationValue::CalculationOperation.new(
            '+', SassC::Script::Value::Number.new(10, 'px'), SassC::Script::Value::Number.new(5, '%')
          )
        )
      end

      def returns_sass_function
        SassC::Script::Value::Function.new('plusOne($n)') do |arguments|
          SassC::Script::Value::Number.new(arguments[0].assert_number.value + 1)
        end
      end
    end
  end
end
