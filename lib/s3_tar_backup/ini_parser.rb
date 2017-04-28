module S3TarBackup
	class IniParser
		@config
		@comments
		@file_path
		@defaults

		def initialize(file_path, defaults={})
			@file_path, @defaults = file_path, defaults
		end

		# Loads the config from file, and parses it
		def load
			if File.exists?(@file_path) && !File.directory?(@file_path)
				File.open(@file_path) do |f|
					@config, @comments = parse_config(f.readlines)
				end
			else
				@config, @comments = {}, {}
			end
			apply_defaults(@defaults)
			self # Allow chaining
		end

		# Saves the config to file
		def save
			File.open(@file_path, 'w') do |f|
				f.write(render_config)
			end
		end

		# Parses a set of lines in a config file, turning them into sections and comments
		def parse_config(config_lines)
			# TODO get rid of all the {:before => [], :after => nil}
			config, comments = {}, {}
			section = nil
			next_comment = {:before => [], :after => nil}

			config_lines.each do |line|
				case line.chomp
				# Section
				when /^\[([\w\-]+)(?: "([\w\-]+)")?\]$/
					section = $1.chomp
					section << ".#{$2.chomp}" if $2
					section = section.to_sym
					config[section] = {} unless config.has_key?(section)
					comments[section] = {} unless comments.has_key?(section)
					next_comment = {:before => [], :after => nil}
					# key line
				when /^([\w\-]+)\s*=\s*([^;]*?)\s*(?:;\s+(.*))?$/
					raise "Config key before section" unless section
					key = $1.chomp.to_sym
					if config[section].has_key?(key)
						config[section][key] = [config[section][key]] unless config[section][key].is_a?(Array)
						config[section][key] << $2.chomp
					else
						config[section][key] = $2.chomp
					end
					# If we found a comment at the end of the line
					next_comment[:after] = $3 if $3
					comments[section][key] = next_comment unless next_comment == {:before => [], :after => nil}
					next_comment = {:before => [], :after => nil}
				when /;\s?(.*)/
					next_comment[:before] << $1
				end
			end

			[config, comments]
		end

		# Applies the defaults passed to the constructor
		def apply_defaults(defaults)
			defaults.each do |key, default|
				section, key = key.match(/(.*)\.(.*)/)[1..2]

				if default.is_a?(Array)
					default_val, comment = default
				else
					default_val, comment = default, nil
				end

				@config[section] = {} unless @config.has_key?(section)
				set("#{section}.#{key}", default_val, comment)
			end
		end

		# Takes the current config, and renders it
		def render_config(comments=true)
			r = ''
			@config.each do |section_key, section|
				section_key_parts = section_key.to_s.split('.')
				if section_key_parts.count > 1
					r << "\n[#{section_key_parts.shift} \"#{section_key_parts.join(' ')}\"]\n\n"
				else
					r << "\n[#{section_key}]\n\n"
				end
				section.each do |key, values|
					values = [*values]
					comments_before, comments_after = '', ''
					if comments && @comments.include?(section_key) && @comments[section_key].include?(key)
						comments_before = @comments[section_key][key][:before].inject(''){ |s,v| s << "; #{v}\n" }
						comments_after = " ; #{@comments[section_key][key][:after]}" if @comments[section_key][key][:after]
					end
					r << comments_before
					r << values.map{ |value| "#{key} = #{value}" }.join("\n")
					r << comments_after << "\n\n"
				end
			end
			r.lstrip.rstrip
		end

		def [](arg)
			get(arg)
		end

		# Used to retrieve a config value, with an optional default.
		# arg: The config key to get, in the form <section>.<key>
		# default: The value to return if the key doesn't exist.
		# This function will use type information from self.defaults / default, if available.
		# Example: config_object.get('section.key', 'default_value')
		def get(arg, default=nil)
			section, key = arg.match(/(.*)\.(.*)/)[1..2]
			section = section.to_sym
			key = key.to_sym

			unless @config.has_key?(section) && @config[section].has_key?(key)
				raise "Tried to access config key #{section}.#{key} which doesn't exist" if default.nil?
				return default
			end

			val = @config[section][key]
			# Is it one of the reserved keywords...?
			case val
			when 'True' then return true
			when 'False' then return false
			when 'None' then return nil
			end

			# Attempt to case... Is there a default?
			if default
				type = default.class
			elsif @defaults.has_key?("#{section}.#{key}")
				type = @defaults["#{section}.#{key}"].class
				# If default is of the form (value, comment)
				type = @defaults["#{section}.#{key}"][0].class if type.is_a?(Array)
			else
				type = nil
			end

			case type
			when Integer
				return val.to_i
			when Float
				return val.to_f
			else
				return val
			end
		end

		def []=(arg, value)
			set(arg, value)
		end

		# Used to set a config value, with optional comments.
		# arg; The config key to set, in the form <section>.<key>
		# comments: The comments to set, if any. If multiple lines are desired, they should be separated by "\n"
		# Example: config_object.set('section.key', 'value', 'This is the comment\nExplaining section.key')
		def set(arg, value, comments=nil)
			section, key = arg.match(/(.*)\.(.*)/)[1..2]
			section = section.to_sym
			key = key.to_sym

			# Is it one of our special values?
			case value
			when true then value = 'True'
			when false then value = 'False'
			when nil then value = 'None'
			end

			@config[section] = {} unless @config.has_key?(section)
			@config[section][key] = value

			if comments
				comments = comments.split("\n")
				@comments[section] = {} unless @comments.has_key?(section)
				@comments[section][key] = {:before => comments, :after => nil}
			end
		end

		def has_section?(section)
			@config.has_key?(section.to_sym)
		end

		def find_sections(pattern=/.*/)
			@config.select{ |k,v| k =~ pattern }
		end

		def each
			@config.each_with_index do |section_key, section|
				section.each_with_index do |key, value|
					key_str = "#{section_key}#{key}"
					yield key_str, get(key_str)
				end
			end
		end
	end
end