S3-tar-backup
=============

About
-----

This tool allows you to backup a set of directories to an Amazon S3 bucket, using incremental backups.
You can then restore the files at a later date.

This tool was built as a replacement for duplicity, after duplicity started throwing errors and generally being a bit unreliable.
It uses command-line tar to create incremental backup snapshots, and the aws-s3 gem to upload these to S3.
It can also optionally use command-line gpg to encrypt backups.

In practice, it turns out that this tool has few lower bandwidth and CPU requirements, and can restore a backup in a fraction of the time that duplicity would take.

Installation
------------

This tool is available as a ruby gem, or you can build it youself.

To install from rubygems: `gem install s3-tar-backup`.

To build it yourself:
```
$ git clone git://github.com/canton7/s3-tar-backup.git
$ cd s3-tar-backup
$ sudo rake install
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

; Set this to the AWS region you want to use
; See http://docs.aws.amazon.com/general/latest/gr/rande.html#s3_region
aws_region = <your aws region>

; The rest of the keys can either be located here, or in your profiles, or both
; The value from the profile will replace the value specified here
full_if_older_than = <timespec>

; Choose one of the following two settings
remove_older_than = <timespec>
remove_all_but_n_full = <number>

backup_dir = </path/to/dir>
dest = <bucket_name>/<path>

; Optional: specifies commands to run before and after each backup
pre-backup = <some command>
post-backup = <some command>

; Optional: defaults to bzip2
compression = <compression_type>

; Optional: defaults to false
always_full = <bool>

; You may choose one of the following two settings
gpg_key = <key ID>    ; Asymmetric encryption
password = <password> ; Symmetric encryption

; You have have multiple lines of the following types.
; Values from here and from your profiles will be combined
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

`dest` is the place where your backups are stored. It consists of the name of the S3 bucket (buckets aren't created automatically), followed by the folder to store objects in, for example `my-backups/tar/`.

`pre-backup` and `post-backup` are two hooks, which are run before and after a backup, respectively.
These lines are optional -- you can have no pre-backup or post-backup lines anywhere in your config if you wish.
Note that `post-backup` is only run after a successful command.
These can be used to do things such as back up a mysql database.
Note that you can have multiple `pre-backup` and `post-backup` lines -- all of the listed commands will be executed.

`compression` gives the compression type.
Valid values are `gzip`, `bzip2`, `lzma`, `lzma2`.
s3-tar-backup is capable of auto-detecting the format of a previously-backed-up archive, and so changing this value will not invalidate previous backups.

`always_full` is an optional key which have have the value `True` or `False`.
This is used to say that incremental backups should never be used.

`gpg_key` is an optional GPG Key ID to use to encrypt backups.
This key must exist in your keyring.
By default, no key is used and backups are not encrypted.
This may not be used at the same time as `password`.

`password` is an optional password to use to encrypt backups.
By default, backups are not encrypted.
This may not be used at the same time as `gpg_key`.

`source` contains the folders to be backed up.

`exclude` lines specify files/dirs to exclude from the backup.
See the `--exclude` option to tar.
The exclude lines are optional -- you can have no exclude lines anywhere in your config if you wish.

**Note:** You can have multiple profiles which use the same `dest` and `backup_dir`.

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

; You may optionally specify one of the two following keys
gpg_key = <key ID>
password = <password>
```

`profile_name` is the name of the profile. You'll use this later.

### Encryption

#### Asymmetric Encryption

`s3-tar-backup` will encrypt your backups if you specify the config key `gpg_key`, which is the ID of the key to use for encrypting backups. 
In order to create an encrypted backup, the public key with this ID must exist in your keyring: it doesn't matter if it has a passphrase or not.
In order to restore an encrypted backup, the private key corresponding to the public key which encrypted the backup must exist in your keyring: your `gpg-agent` will prompt you for the passphrase if required.
The `gpg_key` option is not used when restoring from backup (instead gpg works out which key to use to decrypt the backup by looking at the backup itself), which means that you can safely change the key that `s3-tar-backup` uses to encrypt backups without losing access to older backups.

`s3-tar-backup` works out whether or not to try and decrypt a backup (and whether symmetric or asymmetric encryption is used) by looking at its file extension, which means you can safely enable or disable encryption without losing access to older backups.

To create a key, run `gpg --gen-key`, and follow the prompts.
Make sure you create a backup of the private key using `gpg -a --export-secret-keys <key ID> > s3-tar-backup-secret-key.asc`.

#### Symmetric Encryption

`s3-tar-backup` will encrypt your backups with a symmetric encryption key if the config key `password` is specified, which is the encryption passphrase to use.
This option is used when both encrypting and decrypting backups, which means that `s3-tar-backup` will not be able to decrypt backups it previously created if you change the encryption key. To work around this, you can specify the `--password "my password"` command-line option: if given, this will override the password specified in your configuration file.
If you specify an empty password (`--password ''`), then gpg will prompt you for a password on every file it tries to decrypt. 
To avoid this inconvenience, you should run a full backup whenever you change the encryption key.

**NOTE**: your password is passed to GPG is a command-line flag, and is printed to stdout.
Do **NOT** use this if there are untrusted users on your machine: use asymmetric encryption instead.


### Example config file

```ini
[settings]
aws_access_key_id = ABCD
aws_secret_access_key = ABCDE
aws_region = eu-west-1
; Do a new full backup every 2 weeks
full_if_older_than = 2W
; Keep 5 sets of full backups
remove_all_but_n_full = 5
backup_dir = /root/.backup
dest = my-backups/tar
; You may prefer bzip2, as it has a much lower CPU cost
compression = lzma2
gpg_key = ABCD1234

[profile "www"]
source = /srv/http
; Don't encrypt this (for some reason)
gpg_key =

[profile "home"]
source = /home/me
source = /root
exclude = .backup
; Do full backups less rarely
full_if_older_than = 4W
; Use symmetric encryption for this profile
password = chaatoav6Yiec2aingahrahGulohdoh4

[profile "mysql"]
pre-backup = mysqldump -uuser -ppassword --all-databases > /tmp/mysql_dump.sql
source = /tmp/mysql_dump.sql
post-backup = rm /tmp/mysql_dump.sql
; My MySQL dumps are so small that incremental backups actually add more overhead
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

`--full` will force s3-tar-backup to do a full backup (instead of an incremental one), regardless of which it thinks it should do based on your cofnig file.

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
s3-tar-backup --config <config_file> [--profile <profile>] --restore <restore_dir> [--restore_date <restore_date>] [--password "<password>"] [--verbose]
```

This command will get s3-tar-backup to fetch all the necessary data to restore the latest version of your backup (or an older one if you use `--restore-date`), and stick it into `<restore_dir>`.

Using `<restore_date>`, you can tell s3-tar-backup to restore the first backup before the specified date.
The date format to use is `YYYYMM[DD[hh[mm[ss]]]]`, for example `20110406` means `2011-04-06 00:00:00`, while `201104062143` means `2011-04-06 21:43:00`.

`--verbose` makes tar spit out the files that it restores.

Examples:

```
s3-tar-backup -c ~/.backup/config.ini -p www home --restore my_restore/
s3-tar-backup -c ~/.backup/config.ini -p mysql --restore my_restore/ --restore_date 201104062143
```

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
