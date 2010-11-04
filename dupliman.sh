#!/bin/bash

# -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
#
#  duplyman - A frontend to the duplicity backup software
#
#  duplyman allows to configure duplicity through a default settings file,
#  plus a series of _saveset_ files
#
#
# The MIT License
#
# Copyright (c) 2008 David Losada <david@tuxpiper.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

DEBUG=1

BASEDIR=${0%/*}			# Anchor script to where it's stored
SCRIPTNAME=${0##*/}	# Invoked name
VERSION="0.01"

# Load default config
. ${BASEDIR}/default.cfg.sh

# --------------------------   Aide functions   ------------------------------
ERROR() {
	echo "ERROR: $*" 1>&2
}

WARN() {
	echo "WARN: $*" 1>&2
}

fn_is_declared() {
	declare -f $1 &> /dev/null
	return $?
}

make_abs_path() {
	[ ${1:0:1} == "/" ] && { abs_path=$1 ; return 0 ; }
	abs_path=`pwd`/$1
	return 0;
}

svst_cleanup() {	# Cleanup objects defined (or derived) by saveset file
	[ ! -z "$FINAL_GLOB_FILELIST" ] && rm -f $FINAL_GLOB_FILELIST
	unset ${!SVST_*}
	unset ${!FINAL_*}
	unset svst_pre_backup svst_pre_src svst_post_src
	unset GNUPGHOME PASSPHRASE
	unset AWS_ACCESS_KEY AWS_SECRET_ACCESS_KEY
}

is_s3http_url() {
	[ ${1:0:10} == "s3+http://" ] && return 0 || return 1 ;
}
set_aws_env() {
	is_s3http_url $FINAL_DST || return 1;
	AWS_ACCESS_KEY_ID=${SVST_AWS_ACCESS_KEY_ID:-$DEFAULT_AWS_ACCESS_KEY_ID}
	AWS_SECRET_ACCESS_KEY=${SVST_AWS_SECRET_ACCESS_KEY:-$DEFAULT_AWS_SECRET_ACCESS_KEY}
	export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
}

globbing_filelist() {
	FINAL_GLOB_FILELIST=${BASEDIR}/glob.$$
	cat > $FINAL_GLOB_FILELIST
}

load_svst_file() {		# Set saveset filename, given a saveset name
	# Checks and cleanup
	[ -z "$1" ] && { ERROR "load_svst_file(), specify saveset name!"; return 1; }
	fname=${BASEDIR}/${1}.saveset.sh
	[ -f "$fname" ] || { ERROR "load_svst_file(), can't read $fname"; return 1; }
	svst_cleanup ;
	# Loading
	. $fname || { ERROR "load_svst_file(), error loading saveset"; return 1; }
	unset fname

	# Make up final operation variables
	FINAL_HOST=${SVST_HOST:-$HOST}
	# FINAL_DST:
	patch_dst || { ERROR "load_svst_file(), patching dst" ; return 1; }
	# FINAL_FULL_FREQ
	FINAL_FULL_FREQ=${SVST_FULL_FREQ:-$DEFAULT_FULL_FREQ}
	# FINAL_OPTS:
	FINAL_OPTS="$DUPLICITY_OPTS $SVST_DUP_OPTS"
	FINAL_GPG_KEY=${SVST_GPG_KEY:-$DEFAULT_GPG_KEY}
	if [ -z "$FINAL_GPG_KEY" ] || [ "$FINAL_GPG_KEY" == "NO" ]; then
		FINAL_OPTS="$FINAL_OPTS --no-encryption";
	else
		FINAL_OPTS="$FINAL_OPTS --encrypt-key $FINAL_GPG_KEY --sign-key $FINAL_GPG_KEY ";
	fi
	# GNUPGHOME:
	gpg_home=${SVST_GPG_HOME:-$DEFAULT_GPG_HOME}
	[ ! -z "$gpg_home" ] \
		&& { GNUPGHOME="${BASEDIR}/${gpg_home}" ; export GNUPGHOME ; }
	# PASSPHRASE:
	if [ ! -z "$FINAL_GPG_KEY" ]; then 
		PASSPHRASE=${SVST_GPG_PASSPHRASE:-$DEFAULT_GPG_PASSPHRASE};
		export PASSPHRASE 
	fi

	set_aws_env

	return 0
}

patch_dst() {		# Get final destination after host and saveset id patch
	# If saveset overrides destination
	dst=${SVST_DST:-$DEFAULT_DST}
	# Two values to patch: %HOST% and %SVST_ID%
	if [ -z "$FINAL_HOST" ] || [ -z "$SVST_ID" ]; then
		ERROR "patch_dst(), FINAL_HOST or SVST_ID undefined"
		return 1
	fi
	# Patch through sed
	FINAL_DST=$(echo $dst | 
		sed -e "s/%HOST%/$FINAL_HOST/g" |
		sed -e "s/%SVST_ID%/$SVST_ID/g"
	)
	return 0
}

add_cmd_options() {	# Add command line options
	# Set verbosity
	if [ ! -z "$opt_verbosity" ]; then
		FINAL_OPTS="$FINAL_OPTS -v${opt_verbosity}"
	fi

	# Force full backup (in backup action)
	if [ ! -z "$opt_force_full" ]; then
		FINAL_OPTS="full $FINAL_OPTS"
	fi

	# Force action (generic)
	if [ ! -z "$opt_force" ]; then
		FINAL_OPTS="$FINAL_OPTS --force"
	fi

	# Addition of globbing file (for backup and verify)
	if [ ! -z "$FINAL_GLOB_FILELIST" ]; then
		[ $opt_action == "backup" ] || [ $opt_action == "verify" ] \
		&& { FINAL_OPTS="$FINAL_OPTS --include-globbing-filelist $FINAL_GLOB_FILELIST"; }
	fi

	# If backing up, specifying full frequency
	if [ $opt_action == "backup" ] && [ ! -z "$FINAL_FULL_FREQ" ]; then
		FINAL_OPTS="$FINAL_OPTS --full-if-older-than $FINAL_FULL_FREQ"
	fi

	# Addition of time specification for restoring
	[ ! -z "$opt_time" ] && \
	if [ $opt_action == "restore" ]; then
		FINAL_OPTS="$FINAL_OPTS --restore-time $opt_time"
	fi

	# Addition of files to restore (for resotre)
	if [ $opt_action == "restore" ] && [ ! -z "$opt_extra" ]; then
		local spec;
		for spec in $opt_extra; do 
			FINAL_OPTS="$FINAL_OPTS --file-to-restore $spec"
		done
	fi
	return 0	
}

run_duplicity() {
	[ ! -z "$DEBUG" ] \
		&& { echo "-> Running: $DUPLICITY $*" 1>&2 ; }
	$DUPLICITY $* 
}

get_savesets() {
	SAVESET_LIST=""
	for svst in ${BASEDIR}/*.saveset.sh; do
		local svst1=${svst##*/}	# strip pathname
		local svst_name=${svst1%.saveset.sh} # strip saveset.sh suffix
		[ "$svst_name" == "all" ] \
			&& { WARN "saveset named 'all' will be ignored"; continue; }
		SAVESET_LIST="$SAVESET_LIST $svst_name ";
	done
}

# -------------------------- Actions definition ------------------------------
usage() {		# Print script usage
	cat 1>&2 <<EOF
$SCRIPTNAME - $VERSION
  Usage:
    $SCRIPTNAME <action> [options] [saveset]
  Actions:
    list        - List available savesets
    backup      - Perform backup of a saveset
    verify      - List saveset changes that haven't been copied
    restore     - Restore saveset files
    list-files  - List saveset copied files
    copy-status - Status of the saveset copies
    cleanup     - Cleanup extraneous files (interrupted copies)
EOF

}

# Common function that loads the saveset, prepares command line options
prepare_run() {		# Params: saveset file
	load_svst_file $1 || return 1;
	add_cmd_options || return 1;
	return 0
}

backup_svst() {		# Perform backup of saveset
	prepare_run $1 || return 1 
	# Pre-backup actions?
	fn_is_declared svst_pre_backup \
		&& { svst_pre_backup || { ERROR "While preparing backup..."; return 1; } ; }
	# Before accessing the source..
	fn_is_declared svst_pre_src \
		&& { svst_pre_src || { ERROR "While accessing source..."; return 1; } ; }
	# Run command
	run_duplicity $FINAL_OPTS $SVST_SRC $FINAL_DST
	local retval=$?
	# Post actions..
	fn_is_declared svst_post_backup \
		&& { svst_post_backup || WARN "in post backup action" ; }
	fn_is_declared svst_post_src \
		&& { svst_post_src || WARN "in post src action" ; }
	return $retval
}

verify_svst() {		# Which files have changed?
	prepare_run $1 || return 1
	# Before accessing the source..
	fn_is_declared svst_pre_src \
		&& { svst_pre_src || { ERROR "While accessing source..."; return 1; } ; }
	# Run command
	run_duplicity verify $FINAL_OPTS $FINAL_DST $SVST_SRC 
	local retval=$?
	# Post actions..
	fn_is_declared svst_post_src \
		&& { svst_post_src || WARN "in post src action" ; }
	return $retval
}

collection_status_svst() {		# Which files have changed?
	prepare_run $1 || return 1
	# Run command
	run_duplicity collection-status $FINAL_OPTS $FINAL_DST 
}

list_svst() {		# List files
	prepare_run $1 || return 1
	# Run command
	run_duplicity list-current-files $FINAL_OPTS $FINAL_DST
}

cleanup_svst() {		# Cleanup extraneous files
	prepare_run $1 || return 1
	# Run command
	run_duplicity cleanup $FINAL_OPTS $FINAL_DST
}

restore_svst() {
	# Keep in mind the saveset source becomes the destination of the operation
	if [ -z "$opt_destination" ] && [ -z "$opt_force" ]; then
		echo "NEED CONFIRMATION: for restoring a saveset in the original base dir"
		echo "   you need to provide the '-f' option to the command"
		return 1
	fi
	prepare_run $1 || return 1
	# Default restore destination is saveset source, unless opt_destination
	RESTORE_DST=${opt_destination:-$SVST_SRC}
		
	run_duplicity restore $FINAL_OPTS $FINAL_DST $RESTORE_DST
}

list_savesets() {
	get_savesets 
	for svst in $SAVESET_LIST; do
		echo $svst
		load_svst_file $svst
		echo "  source: $SVST_SRC"
		echo "  destination: $FINAL_DST"
	done
	return 0
}

do_function_on_all() {
	local action_fn=$1; shift;
	if [ "$opt_saveset" == "all" ]; then
		local retval=0;
		get_savesets
		for svst in $SAVESET_LIST; do
			echo "[SAVESET $svst]" 2>&1
			$action_fn $svst $*
			retval=$((retval + $?))
			echo 2>&1
		done
		[ $retval -eq 0 ] && return 0 || return 1;
	else
		$action_fn $opt_saveset $*
		return $?
	fi
}

# --------------------------    MAIN SECTION    ------------------------------

do_parsing() {	# Command line parsing function
	# --> First parameter: action
	opt_action=$1 
	[ -z "$opt_action" ] && { usage; return 1 ; } || shift

	# --> Parse action options
	opt_verbosity=3		# Default duplicity verbosity
	while getopts ":d:t:fFv" curr_option
	do
		case "$curr_option" in
			d)	# Destination
				opt_destination=$OPTARG	;;
			t)	# Time of archive
				opt_time=$OPTARG	;;
			f)  # Force operation
				opt_force="True" ;;
			F)  # Force full backup
				opt_force_full="True" ;;
			v)  # Increase verbosity
				[ "$opt_verbosity" -lt 9 ] && opt_verbosity=$(($opt_verbosity + 1))
				;;
			:)  # Option without argument
				ERROR "Option -$OPTARG requires an argument"
				return 1
				;;
			?)  # Unkown option
				ERROR "Unknown option -$OPTARG"
				return 1
				;;
		esac
	done
	shift $(($OPTIND - 1))
	# Print parsed options
	[ ! -z "$DEBUG" ] && {
		for var in ${!opt_*}; do
			echo -n " * $var: "; eval 'echo $'$var;
		done ;
		echo " * Remaining: $* "
	}

	# --> Rest of arguments (saveset, etc..)
	# Saveset required for..
	case "$opt_action" in
		backup|verify|restore|copy-status|list-files|cleanup)
			[ -z "$1" ] && { ERROR "Please specify a saveset name" ; return 1; }
			opt_saveset=$1 ; shift
			;;
	esac

	opt_extra=$*

}

do_cmd() {	# Do command function
	case "$opt_action" in
		list)
			list_savesets ;
			;;
		backup)
			do_function_on_all backup_svst
			return $?
			;;
		verify)
			do_function_on_all verify_svst
			return $?
			;;
		restore)
			[ $opt_saveset == "all" ] \
				&& { ERROR "won't restore all savesets, do it one by one"; return 1; }
			restore_svst $opt_saveset
			return $?
			;;
		copy-status)
			do_function_on_all collection_status_svst
			return $?
			;;
		list-files)
			do_function_on_all list_svst
			return $?
			;;
		cleanup)
			do_function_on_all cleanup_svst
			return $?
			;;
		*)
			usage; return 1 ;
			;;
	esac
}

do_parsing $* || exit -1
do_cmd 
retval=$?
svst_cleanup

exit $retval

# vim: ts=2
