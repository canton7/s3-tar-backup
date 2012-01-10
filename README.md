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

### Introduction

Configuration is done using an ini file, which can be in the location of your choice.

The config file consists of two sections: a global `[settings]` section, followed by profiles.
With the exception of two keys, every configuration key can be specified either in `[settings]`, in a profile, or both (in which case the profile value is either replaces, or is added to, the value from `[settings]`).

### Global config

```ini
[settings]
; These two keys must be located in this section
; You can use environmental variables instead of these -- see below
aws_access_key_id = <your aws access key>
aws_secret_access_key = <your aws secret key>

; These keys can either be located here, or in your profiles, or both
; The value from the profile will replace the value specified here
full_if_older_than = <timespec>

; Choose one of the following two settings
remove_older_than = <timespec>
remove_all_but_n_full = <number>

backup_dir = </path/to/dir>
dest = <bucket_name>/<path>
pre-backup = <some command>
post-backup = <some command>

compression = <compression_type>

always_full = <bool>

; You have have multiple lines of the following types.
; Value from here and from your profiles will be combined
source = </path/to/another/source>
source = </path/to/another/source>
exclude = </some/dir>
exclude = </some/other/dir>

```

`aws_access_key_id` and `aws_secret_access_key` are fairly obvious -- you'll have been given these when you signed up for S3.
If you can't find them, [look here](http://aws.amazon.com/security-credentials).
You can use the environmental variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY instead if you prefer -- the env vars will override the config options.

`full_if_older_than` tells s3-tar-backup how long if should leave between full backups.  
`<timespec>` is stolen from duplicity. It is given as an interval, which is a number followed by one of the characers s, m, h, D, W, M, or Y (indicating seconds, minutes, hours, days, weeks, months, or years respectively), or a series of such pairs.
For instance, "1h45m" indicates the time that was one hour and 45 minutes ago.
The calendar here is unsophisticated: a month is always 30 days, a year is always 365 days, and a day is always 86400 seconds.

`remove_older_than` tells s3-tar-backup to remove old backups which are older than `<timespec>` (see above for the format of `<timespec>`).

`remove_all_but_n_full` tells s3-tar-backup to remove all backups which were made before the last `n` full backups.

`backup_dir` is the directory used (a) to store temporary data, and (b) to store a record of what files were backed up last time (tar's snar file).
You can delete this dir at any time, but that will slow down the next backup slightly.

`dest` is the place to back the folders up to. It consists of the name of the S3 bucket (buckets aren't create automatically), followed by the folder to store objects in, for example `my-backups/tar/`.

`pre-backup` and `post-backup` are two hooks, which are run before and after a backup, respectively.
These lines are optional -- you can have no pre-backup or post-backup lines anywhere in your config if you wish.
Note that `post-backup` is only run after a successful command.
These can be used to do things such as back up a mysql database.
Note that you can have multiple `pre-backup` and `post-backup` lines -- all of the listed commands will be executed.

`compression` gives the compression type.
Valid values are `gzip`, `bzip2`, `lzma`, `lzma2`.
s3-tar-backup is capable of auto-detecting the format of a previously-backed-up archive, and so changing this value will not invalidate previous backup.

`always_full` is an optional key which have have the value `True` or `False`.
This is used to say that incremental backups should never be used, and is probably only useful when specified inside a profile.

`source` contains the folders to be backed up.

`exclude` lines specify files/dirs to exclude from the backup.
See the `--exclude` option to tar.
The exclude lines are optional -- you can have no exclude lines anywhere in your config if you wish.

**Note:** You can have multiple profiles using the same `dest`, and using the same `backup_dir`.

### Profile config

Next, define your profiles.

Profiles are used to specify, or override from the global config, those config keys which may be specified in either the global config or in a profile.

A profile takes the form:

```ini
[profile "profile_name"]
; You can optionally specify the following keys
backup_dir = </path/to/dir>
source = </path/to/source>
source = </path/to/another/source>
dest = <bucket_name>/<path>
exclude = </some/dir>
pre-backup = <some command>
post-backup = <some command>
```

`profile_name` is the name of the profile. You'll use this later.

### Example config file

```ini
[settings]
aws_access_key = ABCD
aws_secret_access_key = ABCDE
full_if_older_than = 2W
remove_all_but_n_full = 5
backup_dir = ~/.backup
dest = my-backups/tar

[profile "www"]
source = /srv/http

[profile "home"]
source = ~/
source = /root
exclude = .backup
full_if_older_than = 4W

[profile "mysql"]
pre-backup = mysqldump -uuser -ppassword --all-databases > /tmp/mysql_dump.sql
source = /tmp/mysql_dump.sql
post-backup = rm /tmp/mysql_dump.sql
always_full = True
```

Usage
-----

s3-tar-backup works in a number of different modes: backup, restore, cleanup, backup-config, list-backups.

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

### Backup Config file

```
s3-tar-backup --config <config_file> [--profile <profile>] --backup-config [--verbose]
```

This command is used to backup the specified configuration file.
Where it is backed up to depends on your setup: 

 - If you've specified `dest` under `[settings]`, this location is used
 - If you're only got one profile, and `dest` is under this profile, then this location is used.
 - If you have multiple profiles, and there's no `dest` under `[settings]`, you must specify a profile, and this profile's `dest` will be used.
 
### List backups

```
s3-tar-backup --config <config_file> [--profile <profile>] --list-backups [--verbose]
```

This command is used to view information on the current backed-up archives for the specified profile(s) (or all profiles).
This is handy if you need to restore a backup, and want to know things such as how much data you'll have to download, or what dates are available to restore from.