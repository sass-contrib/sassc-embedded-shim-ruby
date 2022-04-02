# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rubocop/rake_task'

task default: %i[rubocop test rails:test]

desc 'Run all tests'
task :test do
  $LOAD_PATH.unshift('lib', 'test')
  Dir.glob('test/**/*_test.rb').sort.each { |f| require_relative f }
end

namespace :git do
  namespace :submodule do
    desc 'Init git submodule'
    task :init do |_, args|
      sh(*%w[git submodule init], *args.extras)
    end

    desc 'Update git submodule'
    task update: :init do |_, args|
      sh(*%w[git submodule update --force], *args.extras)
    end

    desc 'Deinit git submodule'
    task :deinit do |_, args|
      sh(*%w[git submodule deinit --force], *args.extras)
    end
  end
end

namespace :rails do
  desc 'Test sassc-rails'
  task :test do
    submodule = 'vendor/github.com/sass/sassc-rails'
    Rake::Task['git:submodule:update'].invoke(submodule)
    sh(*%w[git apply], File.absolute_path('test/patches/sassc-rails.diff', __dir__), chdir: submodule)
    %w[
      Gemfile
      gemfiles/rails_6_0.gemfile
      gemfiles/sprockets_4_0.gemfile
      gemfiles/sprockets-rails_3_0.gemfile
    ].each do |gemfile|
      Bundler.with_original_env do
        env = { 'BUNDLE_GEMFILE' => gemfile }
        sh(env, *%w[bundle install], chdir: submodule)
        sh(env, *%w[bundle exec rake test], chdir: submodule)
      end
    end
    Rake::Task['git:submodule:deinit'].invoke(submodule)
  end
end

RuboCop::RakeTask.new
