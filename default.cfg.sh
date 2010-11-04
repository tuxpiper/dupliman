# -- Environment settings --
HOST=		# Host denomination where the script is running
DUPLICITY=/usr/bin/duplicity		# Location of the duplicity command

# -------- Default backup settings --------

# --> Generic settings

# DEFAULT_DST - default URL to use. You may use the %HOST% and %SVST_ID%
#     wildcards. The script will substitute those for the hostname and the
#     saveset name respectively
DEFAULT_DST=

# DEFAULT_FULL_FREQ - Full backup frequency. Duplicity will force a full
#     backup when the last full backup is older than the value specified here.
#     You may use the D and M abbreviations, or any other supported by
#     dupicity
DEFAULT_FULL_FREQ=1M    # full backups every month

# --> GPG settings

# DEFAULT_GPG_HOME - home where the GPG keyring is stored
DEFAULT_GPG_HOME=

# DEFAULT_GPG_KEY - hex key identificator of the public key to use for
#     encryption. The private key will be found by association to this key
DEFAULT_GPG_KEY=

# DEFAULT_GPG_PASSPHRASE - passphrase used for protection of the private key
DEFAULT_GPG_PASSPHRASE=

# --> Amazon S3 settings
DEFAULT_AWS_ACCESS_KEY_ID=
DEFAULT_AWS_SECRET_ACCESS_KEY=


