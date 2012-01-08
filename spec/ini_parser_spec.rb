require 's3-tar-backup/ini_parser'
require 'pp'
include S3TarBackup

ini_folder = 'spec/ini_parser'

module S3TarBackup
	class IniParser
		attr_reader :config, :comments
	end
end

describe IniParser do
	it "should load a simple file" do
		par = IniParser.new("#{ini_folder}/simple.ini").load
		par.config.should == {:section => {:key => 'value'}}
	end

	it "should render a simple config file" do
		par = IniParser.new("#{ini_folder}/simple.ini").load
		par.render_config.should == "[section]\n\nkey = value"
	end

	it "should allow reading of config values" do
		par = IniParser.new("#{ini_folder}/simple.ini").load
		par['section.key'].should == 'value'
	end

	it "should allow setting of config values" do
		par = IniParser.new("#{ini_folder}/simple.ini").load
		par['section.key'] = 'new_value'
		par['section.key2'] = 'new_value2'
		par['section2.key'] = 'new_value3'
		par.config.should == {
			:section => {
				:key => 'new_value',
				:key2 => 'new_value2',
			},
			:section2 => {
				:key => 'new_value3',
			}
		}
	end

	it "should listen to defaults when reading config values" do
		par = IniParser.new("#{ini_folder}/simple.ini", {
				'nosection.nokey' => 'my_default',
				'nosection.nokey2' => ['my_default2', 'my_comment'],
		}).load
		par['nosection.nokey'].should == 'my_default'
		par['nosection.nokey2'].should == 'my_default2'
		par.get('nosection.nokey3', 'default').should == 'default'
	end

	it "should load a simple file containing comments" do
		par = IniParser.new("#{ini_folder}/simple_comments.ini").load
		par.config.should == {:section => {:key1 => 'value1', :key2 => 'value2'}}
		par.comments.should == {:section => {
				:key1 => {
					:before => ['Comment before key 1'],
					:after => 'Comment after key 1',
				},
				:key2 => {
					:before => ['Comment before key 2', 'Another comment before key 2'],
					:after => nil,
				},
		}}
	end

	it "should load a file containing special values" do
		par = IniParser.new("#{ini_folder}/special_values.ini").load
		par['section.key1'].should == true
		par['section.key2'].should == false
		par['section.key3'].should == nil
		par['section.key4'].should == 'Hello'
	end

	it "should save special values" do
		par = IniParser.new("#{ini_folder}/simple.ini").load
		par['section.key1'] = true
		par['section.key2'] = false
		par['section.key3'] = nil
		par.config.should == {
			:section => {
				:key => 'value',
				:key1 => 'True',
				:key2 => 'False',
				:key3 => 'None'
			}
		}
	end

	it "should handle files with compound sections" do
		par = IniParser.new("#{ini_folder}/compound_section.ini").load
		par['some_section.my_section.key'].should == 'value'
		par['some_section.my_other_section.key2'] = 'value2'
		par.render_config.should == "[some_section \"my_section\"]\n\nkey = value\n\n\n" \
			"[some_section \"my_other_section\"]\n\nkey2 = value2"
	end
end