# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'
require 'rubocop/rake_task'

task default: %i[rubocop test git:submodule:test]

Rake::TestTask.new do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb']
end

RuboCop::RakeTask.new do |task|
  task.formatters = ['progress']
  task.formatters << 'github' if ENV.key?('GITHUB_ACTIONS')
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

    desc 'Test git submodule'
    task :test do |_, args|
      submodules = if args.extras.empty?
                     %w[
                       vendor/github.com/rails/sprockets
                       vendor/github.com/sass/sassc-rails
                       vendor/github.com/twbs/bootstrap-rubygem
                     ]
                   else
                     args.extras
                   end
      Rake::Task['git:submodule:update'].invoke(*submodules)
      submodules.each do |submodule|
        patch = File.absolute_path("test/patches/#{File.basename(submodule)}.diff", __dir__)
        sh(*%w[git apply], patch, chdir: submodule) if File.exist?(patch)
        case submodule
        when 'vendor/github.com/rails/sprockets'
          Bundler.with_original_env do
            sh(*%w[bundle install], chdir: submodule)
            sh(*%w[bundle exec rake test TEST=test/test_sassc.rb], chdir: submodule)
          end
        when 'vendor/github.com/sass/sassc-rails'
          Bundler.with_original_env do
            gemfiles = %w[
              Gemfile
              gemfiles/rails_6_0.gemfile
              gemfiles/sprockets_4_0.gemfile
              gemfiles/sprockets-rails_3_0.gemfile
            ]
            gemfiles.each do |gemfile|
              env = { 'BUNDLE_GEMFILE' => gemfile, 'MT_COMPAT' => 'true' }
              sh(env, *%w[bundle install], chdir: submodule)
              sh(env, *%w[bundle exec rake test], chdir: submodule)
            end
          end
        when 'vendor/github.com/twbs/bootstrap-rubygem'
          Bundler.with_original_env do
            gemfiles = %w[
              test/gemfiles/rails_6_0.gemfile
              test/gemfiles/rails_6_1.gemfile
              test/gemfiles/rails_7_0_sassc.gemfile
              test/gemfiles/rails_7_0_dartsass.gemfile
            ]
            gemfiles.each do |gemfile|
              env = { 'BUNDLE_GEMFILE' => gemfile }
              sh(env, *%w[bundle install], chdir: submodule)
              sh(env, *%w[bundle exec rake], chdir: submodule)
            end
          end
        end
      end
      Rake::Task['git:submodule:deinit'].invoke(*submodules)
    end
  end
end
