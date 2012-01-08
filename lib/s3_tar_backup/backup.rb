require 'aws/s3'

module S3TarBackup
	class Backup
		@backup_dir
		@name
		@sources
		@exclude
		@time # Here to avoid any sort of race conditions
		@archive


		def initialize(backup_dir, name, sources, exclude)
			@backup_dir, @name, @sources, @exclude, @snar = backup_dir, name, [*sources], [*exclude]
			@time = Time.now
		end

		def snar
			"backup.snar"
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
			File.join(@backup_dir, "backup-#{@name}.#{@time.strftime('%Y%m%d_%H%M%S')}-#{type}.tar.bz2")
		end

		def backup_cmd
			exclude = @exclude.map{ |e| "\"#{e}\""}.join(' ')
			sources = @sources.map{ |s| "\"#{s}\""}.join(' ')
			@archive = archive
			"tar cjf \"#{@archive}\" -g \"#{snar_path}\" --exclude #{exclude} --no-check-device #{sources}"
		end

		def backup

		end


	end
end