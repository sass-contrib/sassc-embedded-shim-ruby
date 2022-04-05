# frozen_string_literal: true

require 'sassc'
require 'sass-embedded'

require 'base64'
require 'json'
require 'uri'

require_relative 'embedded/version'

module SassC
  class Engine
    def render
      return @template.dup if @template.empty?

      result = ::Sass.compile_string(
        @template,
        importer: import_handler.setup(nil),
        load_paths: load_paths,
        syntax: syntax,
        url: file_url,

        source_map: source_map_embed? || !source_map_file.nil?,
        source_map_include_sources: source_map_contents?,
        style: output_style,

        functions: functions_handler.setup(nil, functions: @functions),
        importers: [],

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
      url = e.span&.url
      path = if url&.start_with?('file:')
               URL.parse(url).route_from(URL.path_to_file_url("#{File.absolute_path('')}/"))
             end
      raise SyntaxError.new(e.message, filename: path, line: line)
    end

    private

    def file_url
      @file_url ||= URL.path_to_file_url(File.absolute_path(filename || 'stdin'))
    end

    def output_path
      @output_path ||= @options.fetch(
        :output_path,
        ("#{filename.delete_suffix(File.extname(filename))}.css" if filename)
      )
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
        style = "sass_style_#{style}" unless style.include?('sass_style_')
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
      @load_paths ||= if @options[:importer].nil?
                        (@options[:load_paths] || []) + SassC.load_paths
                      else
                        []
                      end
    end

    def post_process_source_map(source_map)
      return unless source_map

      url = URL.parse(source_map_file_url || file_url)
      data = JSON.parse(source_map)
      data['file'] = URL.parse(output_url).route_from(url).to_s if output_url
      data['sources'].map! do |source|
        if source.start_with?('file:')
          URL.parse(source).route_from(url).to_s
        else
          source
        end
      end

      JSON.generate(data)
    end

    def post_process_css(css)
      css += "\n" unless css.empty?
      unless @source_map.nil? || omit_source_map_url?
        url = URL.parse(output_url || file_url)
        source_mapping_url = if source_map_embed?
                               "data:application/json;base64,#{Base64.strict_encode64(@source_map)}"
                             else
                               URL.parse(source_map_file_url).route_from(url).to_s
                             end
        css += "\n/*# sourceMappingURL=#{source_mapping_url} */"
      end
      css
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
      Importer.new(@importer) if @importer
    end

    class FileImporter
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

          unless ext.empty?
            if from_import
              result = exactly_one(try_path("#{without_ext(path)}.import#{ext}"))
              return result unless result.nil?
            end
            result = exactly_one(try_path(path))
            return result unless result.nil?
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
          return unless dir_exist? path

          if from_import
            result = exactly_one(try_path_with_ext(File.join(path, 'index.import')))
            return result unless result.nil?
          end

          exactly_one(try_path_with_ext(File.join(path, 'index')))
        end

        def exactly_one(paths)
          return if paths.empty?
          return paths.first if paths.length == 1

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

    private_constant :FileImporter

    class Importer
      module Protocol
        FILE = 'file:'
        IMPORT = 'sassc-embedded-import:'
        LOAD = 'sassc-embedded-load:'
        LOADED = 'sassc-embedded-loaded:'
      end

      private_constant :Protocol

      def initialize(importer)
        @importer = importer
        @importer_results = {}
        @parent_urls = [URL.path_to_file_url(File.absolute_path(@importer.options[:filename] || 'stdin'))]
      end

      def canonicalize(url, from_import:)
        return url if url.start_with?(Protocol::IMPORT, Protocol::LOADED)

        if url.start_with?(Protocol::LOAD)
          url = url.delete_prefix(Protocol::LOAD)
          return url if @importer_results.key?(url)

          path = URL.parse(url).route_from(@parent_urls.last).to_s
          resolved = resolve_path(path, URL.file_url_to_path(@parent_urls.last), from_import)
          return URL.path_to_file_url(resolved) unless resolved.nil?

          return
        end

        return unless url.start_with?(Protocol::FILE)

        path = URL.parse(url).route_from(@parent_urls.last).to_s
        parent_path = URL.file_url_to_path(@parent_urls.last)

        imports = @importer.imports(path, parent_path)
        imports = [SassC::Importer::Import.new(path)] if imports.nil?
        imports = [imports] unless imports.is_a?(Array)
        imports.each do |import|
          import.path = File.absolute_path(import.path, File.dirname(parent_path))
        end

        import_url = URL.path_to_file_url(File.absolute_path(path, File.dirname(parent_path)))
        canonical_url = "#{Protocol::IMPORT}#{import_url}"
        @importer_results[canonical_url] = imports_to_native(imports)
        canonical_url
      end

      def load(canonical_url)
        if canonical_url.start_with?(Protocol::IMPORT)
          @importer_results.delete(canonical_url)
        elsif canonical_url.start_with?(Protocol::FILE)
          @parent_urls.push(canonical_url)
          if @importer_results.key?(canonical_url)
            @importer_results.delete(canonical_url)
          else
            path = URL.file_url_to_path(canonical_url)
            {
              contents: File.read(path),
              syntax: syntax(path),
              source_map_url: canonical_url
            }
          end
        elsif canonical_url.start_with?(Protocol::LOADED)
          @parent_urls.pop
          {
            contents: '',
            syntax: :scss
          }
        end
      end

      private

      def load_paths
        @load_paths ||= (@importer.options[:load_paths] || []) + SassC.load_paths
      end

      def resolve_path(path, parent_path, from_import)
        [File.dirname(parent_path)].concat(load_paths).each do |load_path|
          resolved = FileImporter.resolve_path(File.absolute_path(path, load_path), from_import)
          return resolved unless resolved.nil?
        end
        nil
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

      def imports_to_native(imports)
        {
          contents: imports.flat_map do |import|
            file_url = URL.path_to_file_url(import.path)
            if import.source
              @importer_results[file_url] = if import.source.is_a?(Hash)
                                              {
                                                contents: import.source[:contents],
                                                syntax: import.source[:syntax],
                                                source_map_url: file_url
                                              }
                                            else
                                              {
                                                contents: import.source,
                                                syntax: syntax(import.path),
                                                source_map_url: file_url
                                              }
                                            end
            end
            [
              "@import #{"#{Protocol::LOAD}#{file_url}".inspect};",
              "@import #{"#{Protocol::LOADED}#{file_url}".inspect};"
            ]
          end.join("\n"),
          syntax: :scss
        }
      end
    end

    private_constant :Importer
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

    def parse(str)
      PARSER.parse(str)
    end

    def escape(str)
      PARSER.escape(str)
    end

    def unescape(str)
      PARSER.unescape(str)
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
      URI::File.build([nil, escape(path)]).to_s
    end
  end

  private_constant :URL
end
