require 'aws-sdk'

module S3TarBackup
	class Backup
		@backup_dir
		@name
		@sources
		@exclude
		@time # Here to avoid any sort of race conditions
		@archive
		@compression_flag
		@compression_ext
		@gpg_key

		COMPRESSIONS = {
			:gzip => {:flag => '-z', :ext => 'tar.gz'},
			:bzip2 => {:flag => '-j', :ext => 'tar.bz2'},
			:lzma => {:flag => '--lzma', :ext => 'tar.lzma'},
			:lzma2 => {:flag => '-J', :ext => 'tar.xz'}
		}

		ENCRYPTED_EXTENSION = 'asc'


		def initialize(backup_dir, name, sources, exclude, compression=:bzip2, gpg_key=nil)
			@backup_dir, @name, @sources, @exclude = backup_dir, name, [*sources], [*exclude]
			raise "Unknown compression #{compression}. Valid options are #{COMPRESSIONS.keys.join(', ')}" unless COMPRESSIONS.has_key?(compression)
			@compression_flag = COMPRESSIONS[compression][:flag]
			@compression_ext = COMPRESSIONS[compression][:ext]
			@time = Time.now
			@gpg_key = gpg_key

			Dir.mkdir(@backup_dir) unless File.directory?(@backup_dir)
		end

		def snar
			"backup-#{@name}.snar"
		end

		def snar_path
			File.join(@backup_dir, snar)
		end

		def snar_exists?
			File.exists?(snar_path)
		end

		def archive
			return @archive if @archive
			type = snar_exists? ? 'incr' : 'full'
			encrypted_bit = @gpg_key ? ".#{ENCRYPTED_EXTENSION}" : ''
			File.join(@backup_dir, "backup-#{@name}-#{@time.strftime('%Y%m%d_%H%M%S')}-#{type}.#{@compression_ext}#{encrypted_bit}")
		end

		def backup_cmd(verbose=false)
			exclude = @exclude.map{ |e| " --exclude \"#{e}\""}.join
			sources = @sources.map{ |s| "\"#{s}\""}.join(' ')
			@archive = archive
			tar_archive = @gpg_key ? '' : "f \"#{@archive}\""
			gpg_cmd = @gpg_key ? " | gpg -r #{@gpg_key} -o \"#{@archive}\" --always-trust --yes --batch --no-tty -e" : ''
			"tar c#{verbose ? 'v' : ''}#{tar_archive} #{@compression_flag} -g \"#{snar_path}\"#{exclude} --no-check-device #{sources}#{gpg_cmd}"
		end

		def self.parse_object(object, profile)
			name = File.basename(object.key)
			match = name.match(/^backup-([\w\-]+)-(\d\d\d\d)(\d\d)(\d\d)_(\d\d)(\d\d)(\d\d)-(\w+)\.(.*?)(\.#{ENCRYPTED_EXTENSION})?$/)
			return nil unless match && match[1] == profile

			return {
				:type => match[8].to_sym,
				:date => Time.new(match[2].to_i, match[3].to_i, match[4].to_i, match[5].to_i, match[6].to_i, match[7].to_i),
				:name => name,
				:ext => match[9],
				:size => object.content_length,
				:profile => match[1],
				:compression => COMPRESSIONS.find{ |k,v| v[:ext] == match[9] }[0],
				:encryption => !match[10].nil?
			}
		end

		# No real point in creating a whole new class for this one
		def self.restore_cmd(restore_into, restore_from, verbose=false)
			ext, encrypted = restore_from.match(/[^\.\\\/]+\.(.*?)(\.#{ENCRYPTED_EXTENSION})?$/)[1..2]
			compression_flag = COMPRESSIONS.find{ |k,v| v[:ext] == ext }[1][:flag]
			tar_archive = encrypted ? '' : "f \#{restore_from}\""
			gpg_cmd = encrypted ? "gpg --yes --batch --no-tty -d \"#{restore_from}\" | " : ''
			"#{gpg_cmd}tar xp#{verbose ? 'v' : ''}#{tar_archive} #{compression_flag} -G -C #{restore_into}"
		end

	end
end
