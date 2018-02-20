require 's3_tar_backup/backup'
require 'pp'
include S3TarBackup

describe Backup do
  it "should correctly generate the backup command" do
    b = Backup.new('/root/backup', 'my_backup', '/etc', '/etc/test')
    backup_archive = "/root/backup/backup-my_backup.#{Time.now.strftime('%Y%m%d_%H%M%S')}-full.tar.bz2"
    b.archive.should == backup_archive
    backup_snar = '/root/backup/backup.snar'
    b.snar_path.should == backup_snar
    b.snar_exists?.should == File.exists?(backup_snar)
    b.backup_cmd.should == %Q{tar cjf "#{backup_archive}" -g "#{backup_snar}" --exclude "/etc/test" --no-check-device "/etc"}
  end
end