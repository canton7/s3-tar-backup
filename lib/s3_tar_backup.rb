require 'aws/s3'
require 'trollop'
require 's3_tar_backup/ini_parser'
require 's3_tar_backup/backup'
include AWS

module S3TarBackup
	extend self

	def run
		opts = Trollop::options do
			opt :config, "Configuration file", :short => 'c', :type => :string, :required => true
			opt :backup, "Make an incremental backup"
			opt :full_backup, "Make a full backup"
			opt :profile, "The backup profile to use", :short => 'p', :type => :string, :required => true
			conflicts :backup, :full_backup
		end

		raise "Config file #{opts[:config]} not found" unless File.exists?(opts[:config])
		config = IniParser.new(opts[:config]).load
		self.connect_s3(config['settings.aws_access_key_id'], config['settings.aws_secret_access_key'])

		if opts[:backup]
			self.backup_incr(self.gen_backup_config(opts[:profile], config))
		elsif opts[:full_backup]
			self.backup_full(self.gen_backup_config(opts[:profile], config))
		end
	end

	def connect_s3(access_key, secret_key)
		S3::Base.establish_connection!({
			:access_key_id => access_key,
			:secret_access_key => secret_key,
		})
		S3::DEFAULT_HOST.replace("s3-eu-west-1.amazonaws.com")
	end

	def gen_backup_config(profile, config)
		backup_config = {
			:backup_dir => config["backup.#{profile}.backup_dir"],
			:name => profile,
			:sources => [*config["backup.#{profile}.source"]],
			:exclude => [*config.get("backup.#{profile}.exclude", [])],
			:bucket => config["backup.#{profile}.bucket"],
			:dest_prefix => config["backup.#{profile}.prefix"],
		}
		backup_config
	end

	# Config should have the keys
	# backup_dir, name, soruces, exclude, bucket, dest_prefix
	def backup_incr(config, out=$stdout, debug=false)
		out.puts "Starting new incremental backup"
		backup = Backup.new(config[:backup_dir], config[:name], config[:sources], config[:exclude])

		# Try and get hold of the snar file
		unless backup.snar_exists?
			out.puts "Failed to find snar file. Attempting to download..."
			s3_snar = "#{config[:dest_prefix]}/#{backup.snar}"
			if S3::S3Object.exists?(s3_snar, config[:bucket])
				out.puts "Found file on S3. Downloading"
				open(backup.snar_path, 'w') do |f|
					S3::S3Object.stream(s3_snar, config[:bucket]) do |chunk|
						f.write(chunk)
					end
				end
			else
				out.puts "Failed to download snar file. Defaulting to full backup"
			end
		end

		self.backup(config, backup, out, debug)
	end

	def backup_full(config, out=$stdout, debug=false)
		out.puts "Starting new full backup"
		backup = Backup.new(config[:backup_dir], config[:name], config[:sources], config[:exclude])
		# Nuke the snar file -- forces a full backup
		File.delete(backup.snar_path) if File.exists?(backup.snar_path)
		self.backup(config, backup, out, debug)
	end

	def backup(config, backup, out=$stdout, debug=false)
		system(backup.backup_cmd)
		out.puts "Uploading backup #{File.basename(backup.archive)}"
		self.upload(backup.archive, config[:bucket], "#{config[:dest_prefix]}/#{File.basename(backup.archive)}")
		out.puts "Uploading snar"
		self.upload(backup.snar_path, config[:bucket], "#{config[:dest_prefix]}/#{File.basename(backup.snar)}")
		File.delete(backup.archive)
	end

	def upload(source, bucket, dest_name)
		open(source) do |f|
			S3::S3Object.store("#{dest_name}", f, bucket)
		end
	end

end