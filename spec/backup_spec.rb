require 's3_tar_backup/backup'
require 'pp'
include S3TarBackup

describe Backup do
	it "should correctly generate the backup command" do
		b = Backup.new('/root/backup', 'my_backup', '/etc', '/etc/test')
		backup_archive = "/root/backup/backup-my_backup.#{Time.now.strftime('%Y%m%d_%H%M%S')}.tlz"
		b.archive.should == backup_archive
		backup_snar = '/root/backup/backup.snar'
		b.snar.should == backup_snar
		b.snar_exists?.should == File.exists?(backup_snar)
		b.backup_cmd.should == %Q{tar cvf "#{backup_archive}" --lzma -g "#{backup_snar}" --exclude "/etc/test" --no-check-device "/etc"}
	end
end