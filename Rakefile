# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rubocop/rake_task'

task default: %i[rubocop test rails:test]

desc 'Run all tests'
task :test do
  $LOAD_PATH.unshift('lib', 'test')
  Dir.glob('test/**/*_test.rb').sort.each { |f| require_relative f }
end

namespace :rails do
  options = { chdir: 'vendor/github.com/sass/sassc-rails' }

  desc 'Init sassc-rails submodule'
  task :init do
    sh(*%w[git submodule update --init vendor/github.com/sass/sassc-rails])
  end

  desc 'Clean sassc-rails submodule'
  task clean: :init do
    sh(*%w[git reset --hard], **options)
    sh(*%w[git clean -dffx], **options)
  end

  desc 'Patch sassc-rails submodule'
  task patch: :clean do
    sh(*%w[git apply ../../../../test/patches/sassc-rails.diff], **options)
  end

  desc 'Test sassc-rails submodule'
  task test: :patch do
    Bundler.with_original_env do
      %w[
        Gemfile
        gemfiles/rails_6_0.gemfile
        gemfiles/sprockets_4_0.gemfile
        gemfiles/sprockets-rails_3_0.gemfile
      ].each do |gemfile|
        env = { 'BUNDLE_GEMFILE' => gemfile }
        sh(env, *%w[bundle install], **options)
        sh(env, *%w[bundle exec rake test], **options)
      end
    end
    Rake::Task['rails:clean'].execute
  end
end

RuboCop::RakeTask.new
