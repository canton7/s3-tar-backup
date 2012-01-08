require 'aws/s3'
require 'trollop'
require 's3_tar_backup/ini_parser'
require 's3_tar_backup/backup'
require 'pp'
include AWS

module S3TarBackup
	extend self

	def run
		opts = Trollop::options do
			opt :config, "Configuration file", :short => 'c', :type => :string, :required => true
			opt :backup, "Make an incremental backup"
			opt :full, "Make the backup a full backup"
			opt :profile, "The backup profile to use", :short => 'p', :type => :string, :required => true
			opt :cleanup, "Clean up old backups"
			conflicts :backup, :cleanup
		end

		if opts[:full] && !opts[:backup]
			Trollop::die "--full requires --backup"
		end

		raise "Config file #{opts[:config]} not found" unless File.exists?(opts[:config])
		config = IniParser.new(opts[:config]).load
		self.connect_s3(config['settings.aws_access_key_id'], config['settings.aws_secret_access_key'])

		prev_backups = self.parse_objects('creek-backups', 'tar_test/', opts[:profile])

		self.perform_backup(opts, config, prev_backups) if opts[:backup]

		self.perform_cleanup(opts, config, prev_backups) if opts[:backup] || opts[:cleanup]
	end

	def connect_s3(access_key, secret_key)
		S3::Base.establish_connection!({
			:access_key_id => access_key,
			:secret_access_key => secret_key,
		})
		S3::DEFAULT_HOST.replace("s3-eu-west-1.amazonaws.com")
	end

	def perform_backup(opts, config, prev_backups)
		full_required = self.full_required?(config["settings.full_if_older_than"], prev_backups)
		puts "Last full backup is too old. Forcing a full backup" if full_required && !opts[:full_backup]
		if full_required || opts[:full]
			self.backup_full(self.gen_backup_config(opts[:profile], config))
		else
			self.backup_incr(self.gen_backup_config(opts[:profile], config))
		end
	end

	def perform_cleanup(opts, config, prev_backups)
		remove = []
		if age_str = config.get("settings.remove_older_than", false)
			age = self.parse_interval(age_str)
			remove = prev_backups.select{ |o| o[:date] < age }
			# Don't want to delete anything before the last full backup
			removed = remove.slice!(remove.rindex{ |o| o[:type] == :full }..-1).count
			puts "Keeping #{removed} old backups as part of a chain"
		elsif keep_n = config.get("settings.remove_all_but_n_full", false)
			keep_n = keep_n.to_i
			# Get the date of the last full backup to keep
			if last_full_to_keep = prev_backups.select{ |o| o[:type] == :full }[-keep_n]
				# If there is a last full one...
				remove = prev_backups.select{ |o| o[:date] < last_full_to_keep[:date] }
			end
		end
		return if remove.empty?

		puts "Removing #{remove.count} old backup files"
		backup_config = self.gen_backup_config(opts[:profile], config)
		remove.each do |object|
			S3::S3Object.delete("#{backup_config[:dest_prefix]}/#{object[:name]}", backup_config[:bucket])
		end

		#prev_backups.select{ |o| o[:date] < self.parse_interval(config["settings."])}
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
			S3::S3Object.store(dest_name, f, bucket)
		end
	end

	def parse_objects(bucket, prefix, profile)
		objects = []
		S3::Bucket.objects(bucket, :prefix => prefix).each do |object|
			objects << Backup.parse_name(File.basename(object.path), profile)
		end
		objects.compact.sort_by{ |o| o[:date] }
	end

	def parse_interval(interval_str)
		time = Time.now
		time -= $1.to_i if interval_str =~ /(\d+)s/
		time -= $1.to_i*60 if interval_str =~ /(\d+)m/
		time -= $1.to_i*3600 if interval_str =~ /(\d+)h/
		time -= $1.to_i*86400 if interval_str =~ /(\d+)D/
		time -= $1.to_i*604800 if interval_str =~ /(\d+)W/
		time -= $1.to_i*2592000 if interval_str =~ /(\d+)M/
		time -= $1.to_i*31536000 if interval_str =~ /(\d+)Y/
		time
	end

	def full_required?(interval_str, objects)
		time = self.parse_interval(interval_str)
		objects.select{ |o| o[:type] == :full && o[:date] > time }.empty?
	end

end