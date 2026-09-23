# frozen_string_literal: true

require 'sassc'
require 'sass-embedded'

require 'json'
require 'uri'

require_relative 'embedded/version'

module SassC
  class Engine
    remove_method(:render) if public_method_defined?(:render, false)

    def render
      result = ::Sass.compile_string(
        @template,
        importer: (NoopImporter unless @options[:importer].nil?),
        load_paths:,
        syntax:,
        url: file_url,

        charset: @options.fetch(:charset, true),
        source_map: source_map_embed? || !source_map_file.nil?,
        source_map_include_sources: source_map_contents?,
        style: output_style,

        functions: functions_handler.setup(nil, functions: @functions),
        importers: import_handler.setup(nil).concat(@options.fetch(:importers, [])),

        alert_ascii: @options.fetch(:alert_ascii, false),
        alert_color: @options.fetch(:alert_color, nil),
        fatal_deprecations: @options.fetch(:fatal_deprecations, []),
        future_deprecations: @options.fetch(:future_deprecations, []),
        logger: quiet? ? ::Sass::Logger.silent : @options.fetch(:logger, nil),
        quiet_deps: @options.fetch(:quiet_deps, false),
        silence_deprecations: @options.fetch(:silence_deprecations, []),
        verbose: @options.fetch(:verbose, false)
      )

      @loaded_urls = result.loaded_urls
      @source_map = result.source_map

      css = result.css.encode(@template.encoding)
      css << "\n" unless css.empty?
      unless @source_map.nil? || omit_source_map_url?
        source_mapping_url = if source_map_embed?
                               "data:application/json;base64,#{[@source_map].pack('m0')}"
                             else
                               Uri.decode_uri_component(Uri.relative(source_map_file_url, file_url))
                             end
        css << "\n/*# sourceMappingURL=#{source_mapping_url} */"
      end
      css
    rescue ::Sass::CompileError => e
      @loaded_urls = e.loaded_urls

      line = e.span&.start&.line
      line += 1 unless line.nil?
      url = e.span&.url
      filename = (Uri.decode_uri_component(Uri.relative(url, Uri.pwd)) if url&.start_with?('file:'))
      raise SyntaxError.new(e.message, filename:, line:)
    end

    remove_method(:dependencies) if public_method_defined?(:dependencies, false)

    def dependencies
      raise NotRenderedError unless @loaded_urls

      Dependency.from_filenames(@loaded_urls.filter_map do |url|
        Uri.file_uri_to_path(url) if url.start_with?('file:') && !url.include?('?') && url != file_url
      end)
    end

    remove_method(:source_map) if public_method_defined?(:source_map, false)

    def source_map
      raise NotRenderedError unless @source_map

      url = source_map_file_url || file_url
      data = JSON.parse(@source_map)
      data['sources'].map! do |source|
        if source.start_with?('file:')
          Uri.relative(source, url)
        else
          source
        end
      end

      JSON.generate(data).encode!(@template.encoding)
    end

    private

    def file_url
      @file_url ||= Uri.path_to_file_uri(File.absolute_path(filename || 'stdin'))
    end

    def source_map_file_url
      @source_map_file_url ||= if source_map_file
                                 Uri.path_to_file_uri(File.absolute_path(source_map_file))
                                    .gsub('%3F', '?') # https://github.com/sass-contrib/sassc-embedded-shim-ruby/pull/69
                               end
    end

    remove_method(:output_style) if private_method_defined?(:output_style, false)

    def output_style
      @output_style ||= case @options.fetch(:style, :nested).to_sym
                        when :nested, :expanded, :compact, :sass_style_nested, :sass_style_expanded, :sass_style_compact
                          :expanded
                        when :compressed, :sass_style_compressed
                          :compressed
                        else
                          raise InvalidStyleError
                        end
    end

    def syntax
      syntax = @options.fetch(:syntax, :scss).to_sym
      syntax = :indented if syntax == :sass
      syntax
    end

    remove_method(:load_paths) if private_method_defined?(:load_paths, false)

    def load_paths
      @load_paths ||= (@options[:load_paths] || []) + SassC.load_paths
    end
  end

  class FunctionsHandler
    remove_method(:setup) if public_method_defined?(:setup, false)

    def setup(_native_options, functions: Script::Functions)
      functions_wrapper = Class.new do
        attr_accessor :options

        include functions
      end.new
      functions_wrapper.options = @options

      Script.custom_functions(functions:).each_with_object({}) do |custom_function, callbacks|
        callback = lambda do |native_argument_list|
          function_arguments = arguments_from_native_list(native_argument_list)
          result = functions_wrapper.send(custom_function, *function_arguments)
          to_native_value(result)
        rescue StandardError => e
          error(e.message)
          raise
        end

        callbacks[Script.formatted_function_name(custom_function, functions:)] = callback
      end
    end

    private

    remove_method(:arguments_from_native_list) if private_method_defined?(:arguments_from_native_list, false)

    def arguments_from_native_list(native_argument_list)
      native_argument_list.filter_map do |native_value|
        next if native_value.to_nil.nil?

        Script::ValueConversion.from_native(native_value, @options)
      end
    end

    remove_method(:to_native_value) if private_method_defined?(:to_native_value, false)

    def to_native_value(sass_value)
      Script::ValueConversion.to_native(sass_value)
    end

    remove_method(:error) if private_method_defined?(:error, false)

    def error(message)
      warn "[SassC::FunctionsHandler] #{message}"
    end
  end

  module NoopImporter
    module_function

    def canonicalize(...); end

    def load(...); end
  end

  private_constant :NoopImporter

  class ImportHandler
    remove_method(:setup) if public_method_defined?(:setup, false)

    def setup(_native_options)
      if @importer
        import_cache = ImportCache.new(@importer)
        [Importer.new(import_cache), FileImporter.new(import_cache)]
      else
        []
      end
    end

    class Importer
      def initialize(import_cache)
        @import_cache = import_cache
      end

      def canonicalize(...)
        @import_cache.canonicalize(...)
      end

      def load(...)
        @import_cache.load(...)
      end
    end

    private_constant :Importer

    class FileImporter
      def initialize(import_cache)
        @import_cache = import_cache
      end

      def find_file_url(...)
        @import_cache.find_file_url(...)
      end
    end

    private_constant :FileImporter

    module FileSystemImporter
      class << self
        def resolve_path(path, from_import)
          ext = File.extname(path)
          if ['.sass', '.scss', '.css'].include?(ext)
            if from_import
              result = exactly_one(try_path("#{without_ext(path)}.import#{ext}"))
              return result unless result.nil?
            end
            return exactly_one(try_path(path))
          end

          if from_import
            result = exactly_one(try_path_with_ext("#{path}.import"))
            return result unless result.nil?
          end

          result = exactly_one(try_path_with_ext(path))
          return result unless result.nil?

          try_path_as_dir(path, from_import)
        end

        private

        def try_path_with_ext(path)
          result = try_path("#{path}.sass") + try_path("#{path}.scss")
          result.empty? ? try_path("#{path}.css") : result
        end

        def try_path(path)
          partial = File.join(File.dirname(path), "_#{File.basename(path)}")
          result = []
          result.push(partial) if File.file?(partial)
          result.push(path) if File.file?(path)
          result
        end

        def try_path_as_dir(path, from_import)
          return unless File.directory?(path)

          if from_import
            result = exactly_one(try_path_with_ext(File.join(path, 'index.import')))
            return result unless result.nil?
          end

          exactly_one(try_path_with_ext(File.join(path, 'index')))
        end

        def exactly_one(paths)
          return if paths.empty?
          return paths.first if paths.one?

          raise "It's not clear which file to import. Found:\n#{paths.map { |path| "  #{path}" }.join("\n")}"
        end

        def without_ext(path)
          ext = File.extname(path)
          path.delete_suffix(ext)
        end
      end
    end

    private_constant :FileSystemImporter

    class ImportCache
      def initialize(importer)
        @importer = importer
        @importer_results = {}
        @importer_result = nil
        @file_url = nil
      end

      def canonicalize(url, context)
        return unless context.containing_url&.start_with?('file:')

        containing_url = context.containing_url

        path = Uri.decode_uri_component(url)
        parent_path = Uri.file_uri_to_path(containing_url)
        parent_dir = File.dirname(parent_path)

        if containing_url.include?('?')
          canonical_url = Uri.path_to_file_uri(File.absolute_path(path, parent_dir))
          unless @importer_results.key?(canonical_url)
            @file_url = resolve_file_url(path, parent_dir, context.from_import)
            return
          end
        else
          imports = [*@importer.imports(path, parent_path)]
          canonical_url = imports_to_native(imports, parent_dir, context.from_import, url, containing_url)
          unless @importer_results.key?(canonical_url)
            @file_url = canonical_url
            return
          end
        end

        @importer_result = @importer_results.delete(canonical_url)
        canonical_url
      end

      def load(_canonical_url)
        importer_result = @importer_result
        @importer_result = nil
        importer_result
      end

      def find_file_url(_url, context)
        return if context.containing_url.nil? || @file_url.nil?

        canonical_url = @file_url
        @file_url = nil
        canonical_url
      end

      private

      def resolve_file_url(path, parent_dir, from_import)
        resolved = FileSystemImporter.resolve_path(File.absolute_path(path, parent_dir), from_import)
        Uri.path_to_file_uri(resolved) unless resolved.nil?
      end

      def syntax(path)
        case File.extname(path)
        when '.sass'
          :indented
        when '.css'
          :css
        else
          :scss
        end
      end

      def import_to_native(import, parent_dir, from_import, canonicalize)
        if import.source
          canonical_url = Uri.path_to_file_uri(File.absolute_path(import.path, parent_dir))
          @importer_results[canonical_url] = if import.source.is_a?(Hash)
                                               {
                                                 contents: import.source[:contents],
                                                 syntax: import.source[:syntax],
                                                 source_map_url: canonical_url
                                               }
                                             else
                                               {
                                                 contents: import.source,
                                                 syntax: syntax(import.path),
                                                 source_map_url: canonical_url
                                               }
                                             end
          return canonical_url if canonicalize
        elsif canonicalize
          return resolve_file_url(import.path, parent_dir, from_import)
        end

        Uri.encode_uri_path_component(import.path)
      end

      def imports_to_native(imports, parent_dir, from_import, url, containing_url)
        return import_to_native(imports.first, parent_dir, from_import, true) if imports.one?

        canonical_url = "#{containing_url}?url=#{Uri.encode_uri_query_component(url)}&from_import=#{from_import}"
        @importer_results[canonical_url] = {
          contents: imports.map do |import|
            at_rule = from_import ? '@import' : '@forward'
            url = import_to_native(import, parent_dir, from_import, false)
            "#{at_rule} #{Script::Value::String.quote(url)};"
          end.join("\n"),
          syntax: :scss
        }

        canonical_url
      end
    end

    private_constant :ImportCache
  end

  class Sass2Scss
    class << self
      remove_method(:convert) if public_method_defined?(:convert, false)
    end

    def self.convert(sass)
      {
        contents: sass,
        syntax: :indented
      }
    end
  end

  module Script
    remove_const(:Value) if const_defined?(:Value)

    module Value
      def to_h
        assert_map.contents
      end

      def to_s(_options = nil)
        s = nil
        Sass.compile_string('$_: o(#{i()});', functions: { # rubocop:disable Lint/InterpolationCheck
                              'i()' => ->(_) { self },
                              'o($s)' => ->(args) { s = args[0] }
                            })
        s.assert_string.text
      rescue ::Sass::CompileError => e
        raise ::Sass::ScriptError.new(e.message), cause: nil
      end

      def null?
        false
      end

      module Bool
        include Value

        TRUE = ::Sass::Value::Boolean::TRUE.dup
        Bool::TRUE.extend(Bool)

        FALSE = ::Sass::Value::Boolean::FALSE.dup
        Bool::FALSE.extend(Bool)

        class << self
          def new(value)
            value ? Bool::TRUE : Bool::FALSE
          end
        end

        def to_s(_options = {})
          value.to_s
        end
      end

      module Color
        include Value

        def red
          rgba? ? channel('red') : nil
        end

        def green
          rgba? ? channel('green') : nil
        end

        def blue
          rgba? ? channel('blue') : nil
        end

        def hue
          hsla? ? channel('hue') : nil
        end

        def saturation
          hsla? ? channel('saturation') : nil
        end

        def lightness
          hsla? ? channel('lightness') : nil
        end

        class << self
          def new(...)
            ::Sass::Value::Color.new(...)
                                .extend(::SassC::Script::Value::Color)
          end
        end

        def rgba?
          space == 'rgb'
        end

        def hsla?
          space == 'hsl'
        end

        def value
          [*channels, alpha]
        end
      end

      module List
        include Value

        def value
          contents
        end

        class << self
          def new(value, separator: nil, bracketed: false)
            separator = case separator
                        when :comma
                          ','
                        when :space
                          ' '
                        when :slash
                          '/'
                        when :undecided
                          nil
                        else
                          separator
                        end
            ::Sass::Value::List.new(value, separator:, bracketed:)
                               .extend(::SassC::Script::Value::List)
          end
        end
      end

      module Map
        include Value

        def value
          contents
        end

        class << self
          def new(value)
            ::Sass::Value::Map.new(value)
                              .extend(::SassC::Script::Value::Map)
          end
        end
      end

      module Null
        include Value

        NULL = ::Sass::Value::Null::NULL.dup.extend(Null)

        class << self
          def new
            NULL
          end
        end

        def null?
          true
        end

        def to_s(_options = nil)
          ''
        end
      end

      module Number
        include Value

        class << self
          def new(value, numerator_units = nil, denominator_units = nil)
            ::Sass::Value::Number.new(value,
                                      { numerator_units: Array(numerator_units),
                                        denominator_units: Array(denominator_units) })
                                 .extend(::SassC::Script::Value::Number)
          end
        end
      end

      module String
        include Value

        def value
          text
        end

        def type
          quoted? ? :string : :identifier
        end

        class << self
          def quote(contents, options = {})
            contents = ::Sass::Value::String.new(contents, quoted: options[:quote] != :none).to_s
            options[:sass] ? contents.gsub('#', '\#') : contents
          end

          def new(value, type = :identifier)
            ::Sass::Value::String.new(value, quoted: type != :identifier)
                                 .extend(::SassC::Script::Value::String)
          end
        end

        def +(other)
          other_value = if other.is_a?(::SassC::Script::Value)
                          other.to_s(quote: :none)
                        else
                          other.to_s
                        end
          String.new(value + other_value, type)
        end

        def to_s(options = {})
          options = { quote: :none }.merge!(options) unless quoted?
          String.quote(text, options)
        end

        def to_sass(options = {})
          to_s(options.merge(sass: true))
        end
      end
    end

    module ValueConversion
      class << self
        remove_method(:from_native) if public_method_defined?(:from_native, false)
      end

      def self.from_native(value, options)
        case value
        when ::Sass::Value::Null
          SassC::Script::Value::Null::NULL
        when ::Sass::Value::Boolean
          value.value ? ::SassC::Script::Value::Bool::TRUE : ::SassC::Script::Value::Bool::FALSE
        when ::Sass::Value::Color
          value.extend(::SassC::Script::Value::Color)
        when ::Sass::Value::List
          value.instance_variable_set(:@contents, value.instance_variable_get(:@contents).map do |element|
            from_native(element, options)
          end.freeze)
          value.extend(::SassC::Script::Value::List)
        when ::Sass::Value::Map
          value.instance_variable_set(:@contents, value.instance_variable_get(:@contents).to_h do |k, v|
            [from_native(k, options), from_native(v, options)]
          end.freeze)
          value.extend(::SassC::Script::Value::Map)
        when ::Sass::Value::Number
          value.extend(::SassC::Script::Value::Number)
        when ::Sass::Value::String
          value.extend(::SassC::Script::Value::String)
        else
          raise UnsupportedValue, "Sass argument of type #{value.class.name.split('::').last} unsupported"
        end
      end

      class << self
        remove_method(:to_native) if public_method_defined?(:to_native, false)
      end

      def self.to_native(value)
        case value
        when ::Sass::Value
          value
        when nil
          ::Sass::Value::Null::NULL
        else
          raise UnsupportedValue, "Sass return type #{value.class.name.split('::').last} unsupported"
        end
      end
    end
  end

  class SyntaxError
    def detailed_message(...)
      return super unless cause.is_a?(::Sass::CompileError)

      cause.detailed_message(...).gsub(cause.class.name, self.class.name)
    end

    def full_message(...)
      return super unless cause.is_a?(::Sass::CompileError)

      cause.full_message(...).gsub(cause.class.name, self.class.name)
    end
  end

  module Uri
    module_function

    def decode_uri_component(str)
      str.b.gsub(/%\h\h/, ::URI::TBLDECWWWCOMP_).force_encoding(str.encoding)
    end

    def encode_uri_component(str)
      str.b.gsub(/[^0-9A-Za-z\-._~]/n, ::URI::TBLENCURICOMP_).force_encoding(str.encoding)
    end

    def encode_uri_path_component(str)
      str.b.gsub(%r{[^0-9A-Za-z\-._~!$&'()*+,;=:@/]}n, ::URI::TBLENCURICOMP_).force_encoding(str.encoding)
    end

    def encode_uri_query_component(str)
      str.b.gsub(%r{[^0-9A-Za-z\-._~!$&'()*+,;=:@/?]}n, ::URI::TBLENCURICOMP_).force_encoding(str.encoding)
    end

    def file_uri_to_path(uri)
      path = decode_uri_component(::URI::RFC3986_PARSER.parse(uri).path)
      if path.start_with?('/')
        windows_path = path[1..]
        path = windows_path if File.absolute_path?(windows_path)
      end
      path
    end

    def path_to_file_uri(path)
      path = "/#{path}" unless path.start_with?('/')
      "file://#{encode_uri_path_component(path)}"
    end

    def pwd
      pwd = Dir.pwd
      pwd += '/' unless pwd.end_with?('/')
      path_to_file_uri(pwd)
    end

    def relative(to, from)
      ::URI::RFC3986_PARSER.parse(to).route_from(from).to_s
    end
  end

  private_constant :Uri
end
