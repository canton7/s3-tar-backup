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
    @encryption

    COMPRESSIONS = {
      :gzip => {:flag => '-z', :ext => 'tar.gz'},
      :bzip2 => {:flag => '-j', :ext => 'tar.bz2'},
      :lzma => {:flag => '--lzma', :ext => 'tar.lzma'},
      :lzma2 => {:flag => '-J', :ext => 'tar.xz'}
    }

    ENCRYPTED_EXTENSIONS = { :gpg_key => 'asc', :password_file => 'gpg' }
    PASSPHRASE_CIPHER_ALGO = 'AES256'


    def initialize(backup_dir, name, sources, exclude, compression=:bzip2, encryption=nil)
      @backup_dir, @name, @sources, @exclude = backup_dir, name, [*sources], [*exclude]
      raise "Unknown compression #{compression}. Valid options are #{COMPRESSIONS.keys.join(', ')}" unless COMPRESSIONS.has_key?(compression)
      @compression_flag = COMPRESSIONS[compression][:flag]
      @compression_ext = COMPRESSIONS[compression][:ext]
      @time = Time.now
      @encryption = encryption

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
      encrypted_bit = @encryption ? ".#{ENCRYPTED_EXTENSIONS[@encryption[:type]]}" : ''
      File.join(@backup_dir, "backup-#{@name}-#{@time.strftime('%Y%m%d_%H%M%S')}-#{type}.#{@compression_ext}#{encrypted_bit}")
    end

    def backup_cmd(verbose=false)
      exclude = @exclude.map{ |e| " --exclude \"#{e}\""}.join
      sources = @sources.map{ |s| "\"#{s}\""}.join(' ')
      @archive = archive
      tar_archive = @encryption ? '' : "f \"#{@archive}\""
      gpg_cmd = @encryption.nil? ? '' : case @encryption[:type]
      when :gpg_key
        " | gpg -r #{@encryption[:gpg_key]} -o \"#{@archive}\" --always-trust --yes --batch --no-tty -e"
      when :password_file
        " | gpg -c --passphrase-file \"#{@encryption[:password_file]}\" --cipher-algo #{PASSPHRASE_CIPHER_ALGO} -o \"#{@archive}\" --batch --yes --no-tty"
      end
      "tar c#{verbose ? 'v' : ''}#{tar_archive} #{@compression_flag} -g \"#{snar_path}\"#{exclude} --no-check-device #{sources}#{gpg_cmd}"
    end

    def self.parse_object(object, profile)
      name = File.basename(object.key)
      match = name.match(/^backup-([\w\-]+)-(\d\d\d\d)(\d\d)(\d\d)_(\d\d)(\d\d)(\d\d)-(\w+)\.(.*?)(?:\.(#{ENCRYPTED_EXTENSIONS.values.join('|')}))?$/)
      return nil unless match && match[1] == profile

      return {
        :type => match[8].to_sym,
        :date => Time.new(match[2].to_i, match[3].to_i, match[4].to_i, match[5].to_i, match[6].to_i, match[7].to_i),
        :name => name,
        :ext => match[9],
        :size => object.content_length,
        :profile => match[1],
        :compression => COMPRESSIONS.find{ |k,v| v[:ext] == match[9] }[0],
        :encryption => match[10].nil? ? nil : ENCRYPTED_EXTENSIONS.key(match[10])
      }
    end

    # No real point in creating a whole new class for this one
    def self.restore_cmd(restore_into, restore_from, verbose=false, password_file=nil)
      ext, encryption_ext = restore_from.match(/[^\.\\\/]+\.(.*?)(?:\.(#{ENCRYPTED_EXTENSIONS.values.join('|')}))?$/)[1..2]
      encryption = ENCRYPTED_EXTENSIONS.key(encryption_ext)
      compression_flag = COMPRESSIONS.find{ |k,v| v[:ext] == ext }[1][:flag]
      tar_archive = encryption ? '' : "f \"#{restore_from}\""
      gpg_cmd = encryption.nil? ? '' : case encryption
      when :gpg_key
        "gpg --yes -d \"#{restore_from}\" | "
      when :password_file
        flag = password_file && !password_file.empty? ? " --passphrase-file \"#{password_file}\"" : ''
        "gpg --yes#{flag} -d \"#{restore_from}\" | "
      end
      "#{gpg_cmd}tar xp#{verbose ? 'v' : ''}#{tar_archive} #{compression_flag} -G -C #{restore_into}"
    end

  end
end
