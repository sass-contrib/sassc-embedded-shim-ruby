# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rubocop/rake_task'

task default: %i[rubocop test]

desc 'Run all tests'
task :test do
  $LOAD_PATH.unshift('lib', 'test')
  Dir.glob('test/**/*_test.rb').sort.each { |f| require_relative f }
end

RuboCop::RakeTask.new
