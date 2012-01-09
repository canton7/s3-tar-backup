require 'aws/s3'

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

		COMPRESSIONS = {
			:gzip => {:flag => '-z', :ext => 'tar.gz'},
			:bzip2 => {:flag => '-j', :ext => 'tar.bz2'},
			:lzma => {:flag => '--lzma', :ext => 'tar.lzma'},
			:lzma2 => {:flag => '-J', :ext => 'tar.xz'}
		}


		def initialize(backup_dir, name, sources, exclude, compression=:bzip2)
			@backup_dir, @name, @sources, @exclude = backup_dir, name, [*sources], [*exclude]
			raise "Unknown compression #{compression}. Valid options are #{COMPRESSIONS.keys.join(', ')}" unless COMPRESSIONS.has_key?(compression)
			@compression_flag = COMPRESSIONS[compression][:flag]
			@compression_ext = COMPRESSIONS[compression][:ext]
			@time = Time.now
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
			File.join(@backup_dir, "backup-#{@name}-#{@time.strftime('%Y%m%d_%H%M%S')}-#{type}.#{@compression_ext}")
		end

		def backup_cmd(verbose=false)
			exclude = @exclude.map{ |e| "\"#{e}\""}.join(' ')
			sources = @sources.map{ |s| "\"#{s}\""}.join(' ')
			@archive = archive
			"tar c#{verbose ? 'v' : ''}f \"#{@archive}\" #{@compression_flag} -g \"#{snar_path}\" --exclude #{exclude} --no-check-device #{sources}"
		end

		def self.parse_object(object, profile)
			name = File.basename(object.path)
			match = name.match(/^backup-([^\-]+)-(\d\d\d\d)(\d\d)(\d\d)_(\d\d)(\d\d)(\d\d)-([^\.]+)\.(.*)$/)
			return nil unless match && match[1] == profile
			return {
				:type => match[8].to_sym,
				:date => Time.new(match[2].to_i, match[3].to_i, match[4].to_i, match[5].to_i, match[6].to_i, match[7].to_i),
				:name => name,
				:ext => match[9],
				:size => object.size,
			}
		end

		# No real point in creating a whole new class for this one
		def self.restore_cmd(restore_into, restore_from, verbose=false)
			ext = restore_from.match(/[^\.\\\/]+\.(.*)$/)[1]
			compression_flag = COMPRESSIONS.find{ |k,v| v[:ext] == ext }[1][:flag]
			"tar x#{verbose ? 'v' : ''}f #{restore_from} #{compression_flag} -G -C #{restore_into}"
		end

	end
end