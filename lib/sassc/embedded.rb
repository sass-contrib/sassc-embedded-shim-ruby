# frozen_string_literal: true

require 'sassc'
require 'sass-embedded'

require 'base64'
require 'json'
require 'pathname'
require 'uri'

require_relative 'embedded/version'

module SassC
  class Engine
    def render
      return @template.dup if @template.empty?

      result = ::Sass.compile_string(
        @template,
        importer: nil,
        load_paths: load_paths,
        syntax: syntax,
        url: file_url,

        source_map: source_map_embed? || !source_map_file.nil?,
        source_map_include_sources: source_map_contents?,
        style: output_style,

        functions: FunctionsHandler.new(@options).setup(nil, functions: @functions),
        importers: ImportHandler.new(@options).setup(nil),

        alert_ascii: @options.fetch(:alert_ascii, false),
        alert_color: @options.fetch(:alert_color, nil),
        logger: @options.fetch(:logger, nil),
        quiet_deps: @options.fetch(:quiet_deps, false),
        verbose: @options.fetch(:verbose, false)
      )

      @dependencies = result.loaded_urls
                            .filter { |url| url.start_with?('file:') && url != file_url }
                            .map { |url| URL.file_url_to_path(url) }
      @source_map = post_process_source_map(result.source_map)

      return post_process_css(result.css) unless quiet?
    rescue ::Sass::CompileError => e
      line = e.span&.start&.line
      line += 1 unless line.nil?
      path = URL.file_url_to_path(e.span&.url)
      path = relative_path(Dir.pwd, path) unless path.nil?
      raise SyntaxError.new(e.message, filename: path, line: line)
    end

    private

    def output_path
      @output_path ||= @options.fetch(
        :output_path,
        ("#{File.basename(filename, File.extname(filename))}.css" if filename)
      )
    end

    def file_url
      @file_url ||= URL.path_to_file_url(filename || 'stdin')
    end

    def syntax
      syntax = @options.fetch(:syntax, :scss)
      syntax = :indented if syntax.to_sym == :sass
      syntax
    end

    def output_style
      @output_style ||= begin
        style = @options.fetch(:style, :sass_style_nested).to_s
        style = "sass_style_#{style}" unless style.include?('sass_style_')
        raise InvalidStyleError unless OUTPUT_STYLES.include?(style.to_sym)

        style = style.delete_prefix('sass_style_').to_sym
        case style
        when :nested
          :expanded
        when :compact
          :compressed
        else
          style
        end
      end
    end

    def load_paths
      @load_paths ||= (@options[:load_paths] || []) + SassC.load_paths
    end

    def post_process_source_map(source_map)
      return unless source_map

      data = JSON.parse(source_map)

      source_map_dir = File.dirname(source_map_file || '')

      data['file'] = URL.escape(relative_path(source_map_dir, output_path)) if output_path

      data['sources'].map! do |source|
        if source.start_with?('file:')
          relative_path(source_map_dir, URL.file_url_to_path(source))
        else
          source
        end
      end

      JSON.generate(data)
    end

    def post_process_css(css)
      css += "\n" unless css.empty?
      unless @source_map.nil? || omit_source_map_url?
        url = if source_map_embed?
                "data:application/json;base64,#{Base64.strict_encode64(@source_map)}"
              else
                URL.escape(relative_path(File.dirname(output_path || ''), source_map_file))
              end
        css += "\n/*# sourceMappingURL=#{url} */"
      end
      css
    end

    def relative_path(from, to)
      Pathname.new(File.absolute_path(to)).relative_path_from(Pathname.new(File.absolute_path(from))).to_s
    end
  end

  class FunctionsHandler
    def setup(_native_options, functions: Script::Functions)
      @callbacks = {}

      functions_wrapper = Class.new do
        attr_accessor :options

        include functions
      end.new
      functions_wrapper.options = @options

      Script.custom_functions(functions: functions).each do |custom_function|
        callback = lambda do |native_argument_list|
          function_arguments = arguments_from_native_list(native_argument_list)
          begin
            result = functions_wrapper.send(custom_function, *function_arguments)
          rescue StandardError
            raise ::Sass::ScriptError, "Error: error in C function #{custom_function}"
          end
          to_native_value(result)
        rescue StandardError => e
          warn "[SassC::FunctionsHandler] #{e.cause.message}"
          raise e
        end

        @callbacks[Script.formatted_function_name(custom_function, functions: functions)] = callback
      end

      @callbacks
    end

    private

    def arguments_from_native_list(native_argument_list)
      native_argument_list.map do |native_value|
        Script::ValueConversion.from_native(native_value, @options)
      end.compact
    end

    begin
      begin
        raise RuntimeError
      rescue StandardError
        raise ::Sass::ScriptError
      end
    rescue StandardError => e
      unless e.full_message.include?(e.cause.full_message)
        ::Sass::ScriptError.class_eval do
          def full_message(*args, **kwargs)
            full_message = super(*args, **kwargs)
            if cause
              "#{full_message}\n#{cause.full_message(*args, **kwargs)}"
            else
              full_message
            end
          end
        end
      end
    end
  end

  class ImportHandler
    def setup(_native_options)
      if @importer
        [FileImporter.new, Importer.new(@importer)]
      else
        []
      end
    end

    class FileImporter
      def find_file_url(url, **)
        return url if url.start_with?('file:')
      end
    end

    private_constant :FileImporter

    class Importer
      def initialize(importer)
        @importer = importer
        @importer_results = {}
      end

      def canonicalize(url, **)
        path = if url.start_with?('file:')
                 URL.file_url_to_path(url)
               else
                 URL.unescape(url)
               end
        canonical_url = URL.path_to_file_url(File.absolute_path(path))

        if @importer_results.key?(canonical_url)
          return if @importer_results[canonical_url].nil?

          return canonical_url
        end

        canonical_url = "sassc-embedded:#{canonical_url}"

        imports = @importer.imports(path, @importer.options[:filename])
        unless imports.is_a?(Array)
          return if imports.path == path

          imports = [imports]
        end

        dirname = File.dirname(@importer.options.fetch(:filename, 'stdin'))
        contents = imports.map do |import|
          import_url = URL.path_to_file_url(File.absolute_path(import.path, dirname))
          @importer_results[import_url] = if import.source
                                            {
                                              contents: import.source,
                                              syntax: case import.path
                                                      when /\.sass$/i
                                                        :indented
                                                      when /\.css$/i
                                                        :css
                                                      else
                                                        :scss
                                                      end,
                                              source_map_url: if import.source_map_path
                                                                URL.path_to_file_url(
                                                                  File.absolute_path(
                                                                    import.source_map_path, dirname
                                                                  )
                                                                )
                                                              end
                                            }
                                          end
          "@import #{import_url.inspect};"
        end.join("\n")

        @importer_results[canonical_url] = {
          contents: contents,
          syntax: :scss
        }

        canonical_url
      end

      def load(canonical_url)
        @importer_results[canonical_url]
      end
    end

    private_constant :Importer
  end

  module Script
    module ValueConversion
      def self.from_native(value, options)
        case value
        when ::Sass::Value::Null::NULL
          nil
        when ::Sass::Value::Boolean
          ::SassC::Script::Value::Bool.new(value.to_bool)
        when ::Sass::Value::Color
          if value.instance_eval { defined? @hue }
            ::SassC::Script::Value::Color.new(
              hue: value.hue,
              saturation: value.saturation,
              lightness: value.lightness,
              alpha: value.alpha
            )
          else
            ::SassC::Script::Value::Color.new(
              red: value.red,
              green: value.green,
              blue: value.blue,
              alpha: value.alpha
            )
          end
        when ::Sass::Value::List
          ::SassC::Script::Value::List.new(
            value.to_a.map { |element| from_native(element, options) },
            separator: case value.separator
                       when ','
                         :comma
                       when ' '
                         :space
                       else
                         raise UnsupportedValue, "Sass list separator #{value.separator} unsupported"
                       end,
            bracketed: value.bracketed?
          )
        when ::Sass::Value::Map
          ::SassC::Script::Value::Map.new(
            value.contents.to_a.to_h { |k, v| [from_native(k, options), from_native(v, options)] }
          )
        when ::Sass::Value::Number
          ::SassC::Script::Value::Number.new(
            value.value,
            value.numerator_units,
            value.denominator_units
          )
        when ::Sass::Value::String
          ::SassC::Script::Value::String.new(
            value.text,
            value.quoted? ? :string : :identifier
          )
        else
          raise UnsupportedValue, "Sass argument of type #{value.class.name.split('::').last} unsupported"
        end
      end

      def self.to_native(value)
        case value
        when nil
          ::Sass::Value::Null::NULL
        when ::SassC::Script::Value::Bool
          ::Sass::Value::Boolean.new(value.to_bool)
        when ::SassC::Script::Value::Color
          if value.rgba?
            ::Sass::Value::Color.new(
              red: value.red,
              green: value.green,
              blue: value.blue,
              alpha: value.alpha
            )
          elsif value.hlsa?
            ::Sass::Value::Color.new(
              hue: value.hue,
              saturation: value.saturation,
              lightness: value.lightness,
              alpha: value.alpha
            )
          else
            raise UnsupportedValue, "Sass color mode #{value.instance_eval { @mode }} unsupported"
          end
        when ::SassC::Script::Value::List
          ::Sass::Value::List.new(
            value.to_a.map { |element| to_native(element) },
            separator: case value.separator
                       when :comma
                         ','
                       when :space
                         ' '
                       else
                         raise UnsupportedValue, "Sass list separator #{value.separator} unsupported"
                       end,
            bracketed: value.bracketed
          )
        when ::SassC::Script::Value::Map
          ::Sass::Value::Map.new(
            value.value.to_a.to_h { |k, v| [to_native(k), to_native(v)] }
          )
        when ::SassC::Script::Value::Number
          ::Sass::Value::Number.new(
            value.value, {
              numerator_units: value.numerator_units,
              denominator_units: value.denominator_units
            }
          )
        when ::SassC::Script::Value::String
          ::Sass::Value::String.new(
            value.value,
            quoted: value.type != :identifier
          )
        else
          raise UnsupportedValue, "Sass return type #{value.class.name.split('::').last} unsupported"
        end
      end
    end
  end

  module URL
    PARSER = URI::Parser.new({ RESERVED: ';/?:@&=+$,' })

    private_constant :PARSER

    module_function

    def escape(str)
      PARSER.escape(str)
    end

    def unescape(str)
      PARSER.unescape(str)
    end

    def file_url_to_path(url)
      return if url.nil?

      path = unescape(URI.parse(url).path)
      path = path[1..] if Gem.win_platform? && path[0].chr == '/' && path[1].chr =~ /[a-z]/i && path[2].chr == ':'
      path
    end

    def path_to_file_url(path)
      return if path.nil?

      path = File.absolute_path(path)
      path = "/#{path}" unless path.start_with?('/')
      URI::File.build([nil, escape(path)]).to_s
    end
  end

  private_constant :URL
end
