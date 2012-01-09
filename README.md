S3-tar-backup
=============

About
-----

This tool allows you to backup a set of directories to an Amazon S3 bucket, using incremental backups.
You can then restore the files at a later date.

This tool was build as a replacement to duplicity, after duplicity started throwing errors and generally being a bit unreliable.
It uses command-line tar to create incremental backup snapshots, and the aws-s3 gem to upload these to S3.

Installation
------------

This tool is not yet a ruby gem, and unless people ask me, it will remain that way.

Therefore, to install:

```
git clone git@github.com:canton7/s3-tar-backup.git
cd s3-tar-backup
sudo rake install
```

Configuration
-------------

### Global config

Configuration is done using an ini file.

Create this file in the location of your choice, and add the following:

```ini
[settings]
aws_access_key_id = <your aws access key>
aws_secret_access_key = <your aws secret key>
full_if_older_than = <timespec>
; Choose one of the following two settings
remove_older_than = <timespec>
remove_all_but_n_full = <number>
```

`aws_access_key_id` and `aws_secret_access_key` are fairly obvious -- you'll have been given these when you signed up for S3.
If you can't find them, [look here](http://aws.amazon.com/security-credentials).

`full_if_older_than` tells s3-tar-backup how long if should leave between full backups.  
`<timespec>` is stolen from duplicity. It is given as an interval, which is a number followed by one of the characers s, m, h, D, W, M, or Y (indicating seconds, minutes, hours, days, weeks, months, or years respectively), or a series of such pairs.
For instance, "1h45m" indicates the time that was one hour and 45 minutes ago.
The calendar here is unsophisticated: a month is always 30 days, a year is always 365 days, and a day is always 86400 seconds.

`remove_older_than` tells s3-tar-backup to remove old backups which are older than `<timespec>` (see above for the format of `<timespec>`).

`remove_all_but_n_full` tells s3-tar-backup to remove all backups which were made before the last `n` full backups.

### Profile config

Next, define your profiles.
A profile comprises one of more source directories, the bucket to and path to upload to, a temporary directory, and some optional excludes.  
It takes this form:

```ini
[profile "profile_name"]
backup_dir = </path/to/dir>
source = </path/to/source>
; You can have multiple source lines
source = </path/to/another/source>
dest = <bucket_name>/<path>
; The excludes are optional
exclude = </some/dir>
; Again, you can specify multiple
exclude = </some/other/dir>
; The following two keys are optional
pre-backup = <some command>
post-backup = <some command>
```

`profile_name` is the name of the profile. You'll use this later.

`backup_dir` is the directory use (a) to store temporary data, and (b) to store a record of what files were backed up last time (tar's snar file).
You can delete this dir at any time, but that will slow down the next backup slightly.

`source` contains the folders to be backed up.

`dest` is the place to back the folders up to. It consists of the name of the S3 bucket (buckets aren't create automatically), followed by the folder to store objects in.

`exclude` lines specify files/dirs to exclude from the backup.
See the `--exclude` option to tar.

`pre-backup` and `post-backup` are two hooks, which are run before and after a backup, respectively.
Note that `post-backup` is only run after a successful command.
These can be used to do things such as back up a mysql database.

You can have multiple profiles using the same `dest`, and using the same `backup_dir`.

### Example config file

```ini
[settings]
aws_access_key = ABCD
aws_secret_access_key = ABCDE
full_if_older_than = 2W
remove_all_but_n_full = 5

[profile "www"]
backup_dir = ~/.backup
source = /srv/http
dest = my-backups/tar

[profile "home"]
backup_dir = ~/.backup
source = ~/
source = /root
dest = my-backup/tar
exclude = .backup
```

Usage
-----

s3-tar-backup works in three modes: backup, restore, and cleanup.

### Backup

```
s3-tar-backup --config <config_file> [--profile <profile>] --backup [--full] [--verbose]
```

You can use `-c` instead of `--config`, and `-p` instead of `--profile`.

`<config_file>` is the path to the file you created above, and `<profile>` is the name of a profile inside it.
You can also specify multiple profiles.

If no profile is specified, all profiles are backed up.

`--full` will force s3-tar-backup to do a full backup (instead of an incremental one), regardless of whether it thinks it should do one.

`--verbose` will get tar to list the files that it is backing up.

Example:

```
s3-tar-backup -c ~/.backup/config.ini -p www home --backup
```

### Cleanup

**Note:** Cleans are automatically done at the end of each backup.

```
s3-tar-backup --config <config_file> [--profile <profile>] --cleanup
```

s3-tar-backup will go through all old backups, and remove those specified by `remove_all_but_n_full` or `remove_older_than`.

### Restore

```
s3-tar-backup --config <config_file> [--profile <profile>] --restore <restore_dir> [--restore_date <restore_date>] [--verbose]
```

This command will get s3-tar-backup to fetch all the necessary data to restore the latest version of your backup (or an older one if you use `--restore-date`), and stick it into `<restore_dir>`.

Using `<restore_date>`, you can tell s3-tar-backup to restore the first backup before the specified date.
The date format to use is `YYYYMM[DD[hh[mm[ss]]]]`, for example `20110406` means `2011-04-06 00:00:00`, while `201104062143` means `2011-04-06 21:43:00`.

`--verbose` makes tar spit out the files that it restores.