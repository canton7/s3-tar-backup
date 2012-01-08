require 'aws/s3'

module S3TarBackup
	class Backup
		@backup_dir
		@name
		@sources
		@exclude
		@snar
		@time # Here to avoid any sort of race conditions

		def initialize(backup_dir, name, sources, exclude)
			@backup_dir, @name, @sources, @exclude, @snar = backup_dir, name, [*sources], [*exclude]
			@time = Time.now
		end

		def snar
			File.join(@backup_dir, "backup.snar")
		end

		def snar_exists?
			File.exists?(snar)
		end

		def archive
			File.join(@backup_dir, "backup-#{@name}.#{@time.strftime('%Y%m%d_%H%M%S')}.tlz")
		end

		def backup_cmd
			exclude = @exclude.map{ |e| "\"#{e}\""}.join(' ')
			sources = @sources.map{ |s| "\"#{s}\""}.join(' ')
			"tar cvf \"#{archive}\" --lzma -g \"#{snar}\" --exclude #{exclude} --no-check-device #{sources}"
		end

		def backup

		end


	end
end