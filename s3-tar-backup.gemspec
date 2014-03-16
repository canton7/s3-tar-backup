$LOAD_PATH.unshift(File.dirname(File.expand_path(__FILE__)))
require 'lib/s3_tar_backup/version'

spec = Gem::Specification.new do |s|
  s.name = 's3-tar-backup'
  s.version = S3TarBackup::VERSION
  s.summary = 's3-tar-backup: Incrementally backup/restore to Amazon S3 using tar'
  s.description = 'Uses tar\'s incremental backups to backup data to, and restore from, Amazon\'s S3 service'
  s.platform = Gem::Platform::RUBY
  s.authors = ['Antony Male']
  s.email = 'antony dot mail at gmail'
  s.required_ruby_version = '>= 1.9.2'
	s.homepage = 'http://github.com/canton7/s3-tar-backup'

  s.add_dependency 'aws-sdk'

  s.executables  = ['s3-tar-backup']

  s.files = Dir['{bin,lib}/**/*']

end
