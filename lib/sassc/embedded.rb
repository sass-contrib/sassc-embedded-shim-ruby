# frozen_string_literal: true

require 'sassc'
require 'sass-embedded'

require 'json'
require 'uri'

require_relative 'embedded/version'

module SassC
  class Engine
    def render
      return @template.dup if @template.empty?

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
        logger: @options.fetch(:logger, nil),
        quiet_deps: @options.fetch(:quiet_deps, false),
        silence_deprecations: @options.fetch(:silence_deprecations, []),
        verbose: @options.fetch(:verbose, false)
      )

      @loaded_urls = result.loaded_urls
      @source_map = result.source_map

      return if quiet?

      css = result.css
      css += "\n" unless css.empty?
      unless @source_map.nil? || omit_source_map_url?
        url = URL.parse(output_url || file_url)
        source_mapping_url = if source_map_embed?
                               "data:application/json;base64,#{[@source_map].pack('m0')}"
                             else
                               URL.file_urls_to_relative_url(source_map_file_url, url)
                             end
        css += "\n/*# sourceMappingURL=#{source_mapping_url} */"
      end
      css
    rescue ::Sass::CompileError => e
      @loaded_urls = e.loaded_urls

      line = e.span&.start&.line
      line += 1 unless line.nil?
      url = e.span&.url
      path = if url&.start_with?(Protocol::FILE)
               URL.file_urls_to_relative_path(url, URL.path_to_file_url("#{Dir.pwd}/"))
             end
      raise SyntaxError.new(e.full_message, filename: path, line:)
    end

    def dependencies
      raise NotRenderedError unless @loaded_urls

      Dependency.from_filenames(@loaded_urls.filter_map do |url|
        URL.file_url_to_path(url) if url.start_with?(Protocol::FILE) && url != file_url
      end)
    end

    def source_map
      raise NotRenderedError unless @source_map

      url = URL.parse(source_map_file_url || file_url)
      data = JSON.parse(@source_map)
      data['file'] = URL.file_urls_to_relative_url(output_url, url) if output_url
      data['sources'].map! do |source|
        if source.start_with?(Protocol::FILE)
          URL.file_urls_to_relative_url(source, url)
        else
          source
        end
      end

      JSON.generate(data)
    end

    private

    def file_url
      @file_url ||= URL.path_to_file_url(File.absolute_path(filename || 'stdin'))
    end

    def output_path
      @output_path ||= @options.fetch(:output_path) do
        "#{filename.delete_suffix(File.extname(filename))}.css" if filename
      end
    end

    def output_url
      @output_url ||= (URL.path_to_file_url(File.absolute_path(output_path)) if output_path)
    end

    def source_map_file_url
      @source_map_file_url ||= (URL.path_to_file_url(File.absolute_path(source_map_file)) if source_map_file)
    end

    def output_style
      @output_style ||= begin
        style = @options.fetch(:style, :sass_style_nested).to_s
        style = "sass_style_#{style}" unless style.start_with?('sass_style_')
        raise InvalidStyleError unless OUTPUT_STYLES.include?(style.to_sym)

        style = style.delete_prefix('sass_style_').to_sym
        case style
        when :nested, :compact
          :expanded
        else
          style
        end
      end
    end

    def syntax
      syntax = @options.fetch(:syntax, :scss)
      syntax = :indented if syntax.to_sym == :sass
      syntax
    end

    def load_paths
      @load_paths ||= (@options[:load_paths] || []) + SassC.load_paths
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

      Script.custom_functions(functions:).each do |custom_function|
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

        @callbacks[Script.formatted_function_name(custom_function, functions:)] = callback
      end

      @callbacks
    end

    private

    def arguments_from_native_list(native_argument_list)
      native_argument_list.filter_map do |native_value|
        Script::ValueConversion.from_native(native_value, @options)
      end
    end
  end

  module NoopImporter
    module_function

    def canonicalize(...); end

    def load(...); end
  end

  private_constant :NoopImporter

  class ImportHandler
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

    class FileSystemImporter
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
          result.push(partial) if file_exist?(partial)
          result.push(path) if file_exist?(path)
          result
        end

        def try_path_as_dir(path, from_import)
          return unless dir_exist?(path)

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

        def file_exist?(path)
          File.exist?(path) && File.file?(path)
        end

        def dir_exist?(path)
          File.exist?(path) && File.directory?(path)
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
        @file_url = nil
      end

      def canonicalize(url, context)
        return if context.containing_url.nil?

        containing_url = if context.containing_url.start_with?(Protocol::GLOB)
                           URL.unescape(URL.parse(context.containing_url).fragment)
                         else
                           context.containing_url
                         end

        return unless containing_url.start_with?(Protocol::FILE)

        path = URL.unescape(url)
        parent_path = URL.file_url_to_path(containing_url)
        parent_dir = File.dirname(parent_path)

        if containing_url == context.containing_url
          imports = @importer.imports(path, parent_path)
          imports = [SassC::Importer::Import.new(path)] if imports.nil?
          imports = [imports] unless imports.is_a?(Array)
          canonical_url = imports_to_native(imports, parent_dir, context.from_import, url, context.containing_url)
          if @importer_results.key?(canonical_url)
            canonical_url
          else
            @file_url = canonical_url
            nil
          end
        else
          canonical_url = URL.path_to_file_url(File.absolute_path(path, parent_dir))
          if @importer_results.key?(canonical_url)
            canonical_url
          else
            @file_url = resolve_file_url(path, parent_dir, context.from_import)
            nil
          end
        end
      end

      def load(canonical_url)
        @importer_results.delete(canonical_url)
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
        URL.path_to_file_url(resolved) unless resolved.nil?
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
          canonical_url = URL.path_to_file_url(File.absolute_path(import.path, parent_dir))
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

        URL.escape(import.path)
      end

      def imports_to_native(imports, parent_dir, from_import, url, containing_url)
        return import_to_native(imports.first, parent_dir, from_import, true) if imports.one?

        canonical_url = "#{Protocol::GLOB}?#{URL.escape(url)}##{URL.escape(containing_url)}"
        @importer_results[canonical_url] = {
          contents: imports.flat_map do |import|
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
    def self.convert(sass)
      {
        contents: sass,
        syntax: :indented
      }
    end
  end

  module Script
    class Value
      class String
        # Returns the quoted string representation of `contents`.
        #
        # @options opts :quote [String]
        #   The preferred quote style for quoted strings. If `:none`, strings are
        #   always emitted unquoted. If `nil`, quoting is determined automatically.
        # @options opts :sass [String]
        #   Whether to quote strings for Sass source, as opposed to CSS. Defaults to `false`.
        def self.quote(contents, opts = {})
          contents = ::Sass::Value::String.new(contents, quoted: opts[:quote] != :none).to_s
          opts[:sass] ? contents.gsub('#', '\#') : contents
        end

        def to_s(opts = {})
          opts = { quote: :none }.merge!(opts) if @type == :identifier
          self.class.quote(@value, opts)
        end
      end
    end

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

  module Protocol
    FILE = 'file:'
    GLOB = 'sassc-embedded-glob:'
  end

  private_constant :Protocol

  module URL
    PARSER = URI::Parser.new({ RESERVED: ';/?:@&=+$,' })

    private_constant :PARSER

    module_function

    def join(...)
      URI.join(...).to_s
    end

    def parse(str)
      PARSER.parse(str)
    end

    def escape(str)
      PARSER.escape(str)
    end

    def unescape(str)
      PARSER.unescape(str)
    end

    def file_urls_to_relative_url(url, from_url)
      parse(url).route_from(from_url).to_s
    end

    def file_urls_to_relative_path(url, from_url)
      unescape(file_urls_to_relative_url(url, from_url))
    end

    def file_url_to_path(url)
      return if url.nil?

      path = unescape(parse(url).path)
      path = path[1..] if Gem.win_platform? && path[0].chr == '/' && path[1].chr =~ /[a-z]/i && path[2].chr == ':'
      path
    end

    def path_to_file_url(path)
      return if path.nil?

      path = "/#{path}" unless path.start_with?('/')
      "file://#{escape(path)}"
    end
  end

  private_constant :URL
end
