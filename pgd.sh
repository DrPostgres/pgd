#!/bin/bash

# TODO: While in pgconfigure and pgbuild, lock the Git directory so that the
# branch-changes and other Git operations are prohibited for that duration.
# Populate the .git/index.lock file with PID and other info of our process.
# Honor the case where .git is a file and not a direcory.

# This file is typically supposed to be invoked using bash builtin 'source',

# It can also be invoked as
# ./this_script some_command_or_function space_delimited_parameters
#
# For example:
# setupDevEnv.sh pgconfigure --with-bonjour
#
# where pgconfigure is a function defined in this script. The above command will
# invike pgconfigure() function with parameter --with-bonjour.
#
# This is helpful in situations where an IDE (eg. NetBeans) allows you to
# execute scripts with parameters to do some custom action.

# If you don't like the build output to be under the source-code/.git/builds/
# directory, then provide your preference here:
pgdBUILD_ROOT_OVERRIDE=

# Set environment variables needed by the pg* functions below
pgdSetVariables()
{
	# This is where all the build output will be generated, by default. See the
	# function pgdSetGitDir() to see how we influence this variable by changing
	# the $GIT_DIR environment variable of git.
	#
	# Honour the override, if the user has provided one
	if [ "x$pgdBUILD_ROOT_OVERRIDE" != "x" ] ; then
		pgdBUILD_ROOT=$pgdBUILD_ROOT_OVERRIDE
	else # else use the default.
        pgdBUILD_ROOT=$(pwd)_builds
	fi

	pgdSetBuildDirectory
	pgdSetPrefix

	pgdSaved_PGDATA=$PGDATA
	pgdSetPGDATA

	pgdSetPGFlavor
	pgdSetDefaultPort
	pgdSetPSQL
	pgdSetPGSUNAME

	pgdSaved_CSCOPE_DB=$CSCOPE_DB
	# cscope_map.vim, a Vim plugin, uses this environment variable
	export CSCOPE_DB=$pgdBUILD_ROOT/$pgdBRANCH/cscope.out

	pgdSaved_PATH=$PATH
	export PATH=$pgdPREFIX/bin:/mingw/lib:$PATH

	pgdSaved_LD_LIBRARY_PATH=$LD_LIBRARY_PATH
	export LD_LIBRARY_PATH=$pgdPREFIX/lib:$LD_LIBRARY_PATH

    pgdSaved_CCACHE_BASEDIR="$CCACHE_BASEDIR"
    export CCACHE_BASEDIR=$(pwd)

    pgdSaved_CCACHE_NOHASHDIR="$CCACHED_NOHASHDIR"
    export CCACHE_NOHASHDIR=true

	# This will do its job in VPATH builds, and nothing in non-VPATH builds
	mkdir -p $B

	# This will do its job in non-VPATH builds, and nothing in VPATH builds
	mkdir -p $pgdPREFIX
}

pgdInvalidateVariables()
{
	unset pgdBUILD_ROOT

	unset B
	unset pgdPREFIX
	unset pgdFLAVOR
	unset pgdDefaultPort
	unset pgdPSQL
	unset pgdPGSUNAME

	if [ "x$pgdSaved_PATH" != "x" ] ; then
		export PATH=$pgdSaved_PATH
	fi
	unset pgdSaved_PATH

	if [ "x$pgdSaved_CCACHE_HARDLINK" != "x" ] ; then
		:#export CCACHE_HARDLINK=$pgdSaved_CCACHE_HARDLINK
	fi
	unset pgdSaved_CCACHE_HARDLINK

	if [ "x$pgdSaved_CCACHE_BASEDIR" != "x" ] ; then
		export CCACHE_BASEDIR=$pgdSaved_CCACHE_BASEDIR
	fi
	unset pgdSaved_CCACHE_BASEDIR

	if [ "x$pgdSaved_CCACHE_NOHASHDIR" != "x" ] ; then
		export CCACHE_NOHASHDIR=$pgdSaved_CCACHE_NOHASHDIR
	fi
	unset pgdSaved_CCACHE_NOHASHDIR

	if [ "x$pgdSaved_LD_LIBRARY_PATH" != "x" ] ; then
		export LD_LIBRARY_PATH=$pgdSaved_LD_LIBRARY_PATH
	fi
	unset pgdSaved_LD_LIBRARY_PATH

	if [ "x$pgdSaved_PGDATA" != "x" ] ; then
		export PGDATA=$pgdSaved_PGDATA
	else
		unset PGDATA
	fi
	unset pgdSaved_PGDATA

	if [ "x$pgdSaved_CSCOPE_DB" != "x" ] ; then
		export CSCOPE_DB=$pgdSaved_CSCOPE_DB
	else
		unset CSCOPE_DB
	fi
	unset pgdSaved_CSCOPE_DB

	unset pgdBRANCH
}

#If return code is 0, $pgdBRANCH will contain branch name.
pgdSetGitBranchName()
{
	local git_cmd

	if [ "x$pgdGIT_DIR" != "x" ] ; then
		git_cmd="git --git-dir=${pgdGIT_DIR}"
	else
		git_cmd="git"
	fi

	pgdBRANCH=$( $git_cmd branch | grep \* | grep -v "\(no branch\)" | cut -d ' ' -f 2)

	if [ "x$pgdBRANCH" = "x" ] ; then
		echo WARNING: Could not get a branch name
		return 1
	fi

	return 0
}

pgdDetectBranchChange()
{
	pgdSetPGFlavor >/dev/null 2>&1

	if [ $? -ne 0 ] ; then
		echo Not in Postgres sources 1>&2
		pgdInvalidateVariables
		return 1
	fi

	local pgdSAVED_BRANCH_NAME=$pgdBRANCH

	pgdSetGitBranchName

	if [ $? -ne 0 ] ; then
		return 1
	fi

	if [ "x$pgdSAVED_BRANCH_NAME" != "x$pgdBRANCH" ] ; then
		# Do these operations only on a branch change.
		pgdInvalidateVariables
		pgdSetVariables
	fi

	return 0
}

# set $B to the location where builds should happen
pgdSetBuildDirectory()
{
	if [ "x$pgdBRANCH" = "x" ] ; then
		pgdSetGitBranchName
	fi

	if [ $? -ne 0 ] ; then
		return 1
	fi

	# If the optional parameter is not provided
	if [ "x$1" = "x" ] ; then
		# $pgdBUILD_ROOT is absolute path, hence we need not use the `cd ...; pwd`
		# trick here.
		export B=$pgdBUILD_ROOT/$pgdBRANCH
	else
		export B=`cd $1; pwd`
	fi

	return 0
}

# Set Postgres' installation prefix directory
pgdSetPrefix()
{
	if [ "x$pgdBRANCH" = "x" ] ; then
		pgdSetGitBranchName
	fi

	if [ $? -ne 0 ] ; then
		return 1
	fi

	# We're not using $B/db here, since in non-VPATH builds $B is the same as
	# source directory, and we don't want the build output to land there.
	pgdPREFIX=$pgdBUILD_ROOT/$pgdBRANCH/db

	return 0
}

#Set $PGDATA
pgdSetPGDATA()
{
	if [ "x$pgdPREFIX" = "x" ] ; then
		pgdSetPrefix
	fi

	if [ $? = "0" ] ; then
		# If the optional parameter is not provided
		if [ "x$1" = "x" ] ; then
			export PGDATA=$pgdPREFIX/data
		else # .. use the data directory provided by the user
			export PGDATA=`cd $1; pwd`
		fi

		return 0
	fi

	return 1
}

# Check if $PGDATA directory exists
pgdCheckDATADirectoryExists()
{
  if [ ! -d $PGDATA ] ; then
    echo ERROR: \$PGDATA not set\; $PGDATA, no such directory 1>&2
    return 1;
  fi;

  return 0;
}

pgdSetSTARTShell()
{
	# It is a known bug that on MinGW's rxvt, psql's prompt doesn't show up; psql
	# works fine, it's just that the prompt is always missing, hence we have to
	# start a new console and assign it to psql
	if [ X$MSYSTEM = "XMINGW32" ] ; then
		pgdSTART='start '
	else
		pgdSTART=' '
	fi

	return 0
}

pgdSetPGFlavor()
{
	local src_dir
	local autoconf_input

	if [ "x$pgdGIT_DIR" != "x" ] ; then
		src_dir=$pgdGIT_DIR/../
	else
		src_dir=`pwd`
	fi

	# Newer versions of Postgres uses file named configure.ac
	autoconf_input=$( [[ -f "$src_dir/configure.in" ]] && echo "$src_dir/configure.in" || echo "$src_dir/configure.ac" )

	if [[ -z "$autoconf_input" ]] ; then
		echo "WARNING: Are you sure that $src_dir is a Postgres source directory?" 1>&2
		return 1
	fi

	# If the configure.in file contains the word EnterpriseDB, then we're
	# working with EnterpriseDB sources.
	grep -m 1 EnterpriseDB "$autoconf_input" 2>&1 > /dev/null
	if [ $? -eq 0 ] ; then
		pgdFLAVOR="edb"
		return 0
	fi

	# If the configure.in file contains the word PostgreSQL, then we're working
	# with Postgres sources.
	grep -m 1 PostgreSQL "$autoconf_input" 2>&1 > /dev/null
	if [ $? -eq 0 ] ; then
		pgdFLAVOR="postgres"
		return 0
	fi

	return 1
}

# Set the default port number for the flavor of Postgres we're developing. Must
# be called _after_ pgdSetPGFlavor() has been called.
pgdSetDefaultPort()
{
	if [[ "$pgdFLAVOR" == "postgres" ]]; then
		pgdDefaultPort=5432
	elif [[ "$pgdFLAVOR" == "edb" ]]; then
		pgdDefaultPort=5444
	fi
}

pgdSetPSQL()
{
	if [ "x$pgdFLAVOR" = "x" ] ; then
		pgdSetPGFlavor
	fi

	if [ "x$pgdFLAVOR" = "xpostgres" ] ; then
		pgdPSQL=psql
	elif [ "x$pgdFLAVOR" = "xedb" ] ; then
		pgdPSQL=edb-psql
	fi
}

pgdSetPGSUNAME()
{
	if [ "x$pgdFLAVOR" = "x" ] ; then
		pgdSetPGFlavor
	fi

	if [ "x$pgdFLAVOR" = "xpostgres" ] ; then
		pgdPGSUNAME=postgres
		pgdDBNAME=postgres
	elif [ "x$pgdFLAVOR" = "xedb" ] ; then
		pgdPGSUNAME=enterprisedb
		pgdDBNAME=edb
	fi
}

##########
# The real commands supposed to be used by the user
#########

pgsql()
{
	pgdDetectBranchChange || return $?

	local port=$(pgdGetServerPortNumber)
	local port_option

	if [[ "$port" == "" ]]; then
		port_option=""
	else
		port_option="-p $port"
	fi

	# This check is not part of pgdDetectBranchChange() because a change in
	# branch does not affect this variable
	if [ "x$pgdSTART" = "x" ] ; then
		pgdSetSTARTShell
	fi

	# By default connect as superuser, to the default database. This will be
	# overridden if the user calls this function as
	# `pgsql -U someotherUser -d someotherDB`
	$pgdSTART$pgdPREFIX/bin/$pgdPSQL $port_option -U $pgdPGSUNAME -d $pgdDBNAME "$@"

	local ret_code=$?

	# ~/.psqlrc changes the terminal title, so change it back to something
	# sensible.
	# Disabling this for now, since it doesn't always work, and in fact this
	# echo emits unnecessary output in log files, or in `less` scrolling.
	#echo -en '\033]2;Terminal\007'

	return $ret_code
}

pginitdb()
{
	pgdDetectBranchChange || return $?

	$pgdPREFIX/bin/initdb -D $PGDATA -U $pgdPGSUNAME
}

pgstart()
{
	pgdDetectBranchChange || return $?

	pgdCheckDATADirectoryExists || return $?

	{
	# Set $PGUSER to DB superuser's name so that `pg_ctl -w` can connect to
	# instance, to be able to check its status

	local PGUSER=$pgdPGSUNAME
	export PGUSER

	local port=$(pgdChooseServerPortNumber)
	local port_option

	if [[ "$port" == "" ]]; then
		port_option=""
	else
		port_option="-p $port"
	fi

	# use pgstatus() to check if the server is already running
	pgstatus || $pgdPREFIX/bin/pg_ctl -D $PGDATA -l $PGDATA/server.log -w start -o"$port_option" "$@"
	}

	# Record pg_ctl's return code, so that it can be returned as return value
	# of this function.
	local ret_value=$?

	$pgdPREFIX/bin/pg_controldata $PGDATA | grep 'Database cluster state'

	return $ret_value
}

pgstatus()
{
	pgdDetectBranchChange || return $?

	pgdCheckDATADirectoryExists || return $?

	# if we adorn the variable with 'local' keyword, then pg_ctl's exit code is
	# lost; hence we prefix it with pgd and unset it before returning.
	pgdpg_ctl_output=$($pgdPREFIX/bin/pg_ctl -D $PGDATA status)

	local rc=$?

	# Emit the pg_ctl output to stdout or stderr depending on whether or not the
	# pg_ctl command succeeded.
	#
	# We have to wrap the $pgdpg_ctl_output in double quotes, because otherwise
	# echo does not print the newline characters in the content of that variable
	if [ $rc -eq 0 ] ; then
		echo "$pgdpg_ctl_output"
	else
		echo "$pgdpg_ctl_output" 1>&2
	fi

	unset pgdpg_ctl_output
	return $rc
}

pgreload()
{
	pgdDetectBranchChange || return $?

	pgdCheckDATADirectoryExists || return $?

	$pgdPREFIX/bin/pg_ctl -D $PGDATA reload

	return $?
}

pgstop()
{
	pgdDetectBranchChange || return $?

	# Call pgstatus() to check if the server is running.
	pgstatus && $pgdPREFIX/bin/pg_ctl -D $PGDATA stop "$@"
}

pgconfigure()
{
	pgdDetectBranchChange || return $?

	local src_dir

	if [ "x$pgdGIT_DIR" != "x" ] ; then
		src_dir=$pgdGIT_DIR/../
	else
		src_dir=`pwd`
	fi

	# If we have ccache and gcc installed, then we use them together to improve
	# compilation times.
	local ccacher
	which ccache &>/dev/null
	if [ $? -eq 0 ] ; then
		which gcc &>/dev/null
		if [ $? -eq 0 ] ; then
			ccacher="ccache gcc"
		fi
	fi

	case $OSTYPE in
	darwin*)
		# The libedit library (aliased as libreadline on MacOS) is not very
		# advanced. Hence, use Homebrew's version of libreadline.
		#
		# Also, use OpenSSL from Homebrew, since macOS does not ship with
		# requisite header files.
		#
		# Use these commands to install these dependencies:
		# $ brew install openssl readline
		#
		local pgdLDFLAGS="${LDFLAGS} -L/usr/local/opt/readline/lib -L/usr/local/opt/openssl/lib"
		local pgdCPPFLAGS="${CPPFLAGS} -I/usr/local/opt/readline/include -I/usr/local/opt/openssl/include"
		;;
	*)
		;;
	esac

	# If $ccacher variable is not set, then ./configure behaves as if CC variable
	# was not specified, and uses the default mechanism to find a compiler.
	( mkdir -p $B	\
		&& cd $B	\
		&& $src_dir/configure --config-cache --prefix=$pgdPREFIX CC="${ccacher}" --enable-debug --enable-cassert CFLAGS=-O0 CPPFLAGS="${pgdCPPFLAGS}" LDFLAGS="${pgdLDFLAGS}" --enable-depend --enable-thread-safety --with-openssl "$@" )

	return $?
}

pgmake()
{
	pgdDetectBranchChange || return $?

	# Use GNU-make, if available
	which gmake >/dev/null 2>&1
	if [ $? == "0" ] ; then
		MAKER=gmake
	else
		MAKER=make
	fi

	# Append "$@" to the command so that we can do `pgmake -C src/backend/`, or
	# anything similar. `make` allows multiple -C options, and the options
	# specified later take precedence.
	$MAKER -C "$B" --no-print-directory "$@"

	return $?
}

pgdlsfiles()
{
	pgdDetectBranchChange || return $?

	local src_dir

	if [ "x$pgdGIT_DIR" != "x" ] ; then
		src_dir=$pgdGIT_DIR/../
	else
		src_dir=`pwd`
	fi

	local vpath_src_dir

	#  If working in VPATH build
	if [ $B = `cd $pgdBUILD_ROOT/$pgdBRANCH; pwd` ] ; then
		vpath_src_dir=$B/src/

		# If the src/ directory under build directory doesn't exist yet (this
		# may happen in VPATH builds when pgconfigure hasn't been run yet), then
		# don't use this variable.
		if [ ! -d $vpath_src_dir ] ; then
			vpath_src_dir=
		fi
	else
		vpath_src_dir=
	fi

	local find_opts

	if [ "x$1" != "x--no-symlink" ] ; then
		find_opts=-L
	else
		find_opts=
		shift # Consume the option we just honored
	fi

	# Emit a list of all interesting files.
	( cd $src_dir && find $find_opts ./src/ ./contrib/ "$vpath_src_dir" -type f -iname "*.[chyl]" -or -iname "*.[ch]pp" -or -iname "README*" )
}

pgdcscope()
{
	# If we're not in Postgres sources, cscope in the next command will hang
	# until interrupted, so bail out sooner if we're not in PG sources.
	pgdDetectBranchChange || return $?

	# Emit a list of all source files,and make cscope consume that list from stdin
	pgdlsfiles --no-symlink | cscope -Rb -f $CSCOPE_DB -i -
}

# unset $GIT_DIR
pgdUnsetGitDir()
{
	unset pgdGIT_DIR
}

# Set the directory which contains Postgres source code
#
# Specifically, this directory should contain a .git/ directory and Postgres
# source code checked-out from that directory.
#
# If provided with a parameter, set the variable to that directory else set the
# variable to `pwd`
pgdSetGitDir()
{
	if [ "x$1" != "x" ] ; then
		pgdGIT_DIR=`cd "$1"; pwd`/.git/
	else
		pgdGIT_DIR=`pwd`/.git
	fi

	export pgdGIT_DIR
}

# All the functions defined in this file are available to interactive shells,
# but not available to non-interactive (n-i) shells since n-i shells do not
# process .bashrc or .bash_profile files.
#
# Emit a comma separated list of pids of all processes in this process' tree
getPIDTree()
{
	local PID=$1
	if [ -z $PID ]; then
	    echo "ERROR: No pid specified" 1>&2
		return 1
	fi

	local PPLIST=$PID
	local CHILD_LIST=$(pgrep -P $PPLIST -d,)

	while [ ! -z "$CHILD_LIST" ] ; do
		# Remove trailing comma, if any
		CHILD_LIST=$(echo $CHILD_LIST | sed 's/,$//')
		PPLIST="$PPLIST,$CHILD_LIST"
		CHILD_LIST=$(pgrep -P $CHILD_LIST -d,)
	done

	echo $PPLIST
}

# Show postmaster and all its children, as a process tree
pgserverprocesses()
{
	local server_process_pids=$(pgserverPIDList)

	if [ -z "$server_process_pids" ] ; then
		return 1;
	fi

	# We use a dummy grep because otherwise the 'u' option causes the long lines
	# in output to be stripped at terminal edge. With this dummy grep, the long
	# lines wrap around to next line.
	ps fu -p $server_process_pids | grep ''

	unset server_process_pids
}

# Emit a comma-separated list of PIDs of Postmaster and its children
pgserverPIDList()
{
	# Make sure we're in postgres source directory
	pgdDetectBranchChange || return $?

	# Make sure postgres server is running. Suppress output only if successful.
	# That is, show only stderr stream of the pgstatus().
	pgstatus >/dev/null || return $?

	echo $(getPIDTree $(head -1 "$PGDATA"/postmaster.pid))
}

# Show a list (actually, forest) of all processes related to postgres.
pgshowprocesses()
{
	# Exclude the 'grep' processes from the list
	#
	# Postgres versions 8.1 and prior used the posmaster binary, and later
	# versions use the postgres binary. So look for both postmaster and postgres
	# in the process status.
	ps faux | grep -vw grep | grep -wE 'postmaster|postgres'
}

pgdChooseServerPortNumber()
{
	# This function is suitable only for Unix (e.g. Darwin), and not for Linux.
	# On all other OS, we simply return the default port number.
	# TODO: Implement support for common Linux distributions.

	local port

	case $OSTYPE in
	darwin*)

		# Get a list of ports already in use.
		#
		# The below method tries to avoid only the ports that are already being
		# listened on. But there may be other ports that are in use because they
		# are used by inbound connections. See an example below. In this case,
		# trying to use ports 65517 (or 62310) for Postgres will lead to the OS
		# rejecting Postgres' attempt to open port this port on IPv4. However, If
		# the requested port is available on IPv6, Postgres will start up and serve
		# IPv6 traffic (only); in this case you'll see a WARNING in Postgres server
		# logs, complaining about unable to open port on 127.0.0.1.
		#
		# TODO: Parse and exclude ports of this kind, as well.
		#
		# some-process    93623      502  126u  IPv4 0x8123bac7737ef29      0t0  TCP 127.0.0.1:65517->127.0.0.1:62310 (ESTABLISHED)
		#
		# On Darwin, a typical output of `lsof -lnPi | grep -E 'LISTEN\)$'` is as
		# follows:
		#
		#	 rapportd	549	  502	4u  IPv4 0x8123bac18b43909	  0t0  TCP *:58255 (LISTEN)
		#	 rapportd	549	  502	5u  IPv6 0x8123bac35e203d9	  0t0  TCP *:58255 (LISTEN)
		#	 postgres  35810	  502	7u  IPv6 0x8123bac144bf179	  0t0  TCP [::1]:5433 (LISTEN)
		#	 postgres  35810	  502	8u  IPv4 0x8123bacf22062e9	  0t0  TCP 127.0.0.1:5433 (LISTEN)
		#	 Google	93623	  502   54u  IPv6 0x8123bad100d9eb9	  0t0  TCP [::1]:7679 (LISTEN)
		#	 Google	93623	  502  124u  IPv4 0x8123bac77382089	  0t0  TCP 127.0.0.1:65517 (LISTEN)
		#	 Google	93623	  502  206u  IPv4 0x8123bad1287a6a9	  0t0  TCP 127.0.0.1:65496 (LISTEN)
		#
		# So the following command is used to parse and capture all the port
		# numbers from such an output.
		#
		# Execute `lsof -lnPi` and grep only those lines that _end_ with 'LISTEN)'
		# Reverse each line's contents to ensure the first : (colon) character now
		# _follows_ the port number. Use colon and space delimiters to strip away
		# everything else. Reverse once more to revert the previous revrse.
		# Finally, remove any duplicates by using sort and uniq. The sort helps
		# because the comm command, used later here, requires it.
		#
		# Note that the value of the active_ports is a multi-line string.
		local active_ports=$(lsof -lnPi | grep -E 'LISTEN\)$' | rev | cut -d: -f 1 | rev | cut -d' ' -f 1 | sort | uniq)

		# If the default port is not in use, it makes our life much easier.
		echo "$active_ports" | grep -q $pgdDefaultPort
		if [[ $? -eq 1 ]]; then
			port=$pgdDefaultPort
		else
			# Default port is not available, so we need to choose one that's not in use
			# by anything else.
			port=$(comm -23 <(seq 5432 65535 | sort) <(echo "$active_ports") | shuf | head -1)
		fi
		;;
	*)
		port=$pgdDefaultPort
		;;
	esac

	echo $port
}

# Get the port number from the running server
pgdGetServerPortNumber()
{
	local port

	# Extract and return port number, iff server is running
	pgstatus >/dev/null								 \
	&& port=$(head -4 $PGDATA/postmaster.pid | tail -1) \
	&& echo $port
}

# Set and export environment variable PGPORT
# This is useful for utilities that use this variable (e.g. pg_dump)
#
# TODO: We desperately need to develop a facility that lets us prance around in
# various source directories (that may in turn have many branches that we can
# switch between at whim) and this facility should keep track of all the
# variables (exported or otherwise) and change them appropriately on every
# directory or branch switch.
#
# Something akin to the following set of functions:
# pgdSetSourceDir
#   Pushes the current variable values on a stack, and adopts values for the
#   new (directory,branch) pair. If the pair already exists in the stack, then
#   use values from that stack entry, and put that entry at the top of the
#   stack.
#   This function should take one parameter, the directory path. It should set
#   all the relevant parameters even if CWD is not under that directory. This
#   is helpful for extension development.
#
# pgdResetDirecctoryStack
#   Reset environment to the initial state, as if we have never entered a
#   Postgres source directory.
#
# pgdGeneratePortNumber
#   echo "$(echo "obase=10; ibase=16; $(echo dir_branch_pair | md5sum | cut -d' ' -f 1 | tr '[:lower:]' '[:upper:]')" | bc) % (65535 - 1024) + 1024" | bc
#
pgdExportPGPORT()
{
	local port=$(pgdGetServerPortNumber)

	if [[ "$port" == "" ]]; then
		return 1
	else
		export PGPORT=$port \
		&& echo "PGPORT(=$port) exported"  \
		&& return 0
	fi
}

createBuildRootReadme()
{
	cat > $pgdBUILD_ROOT/README << EOF
This directory is managed by pgd (https://github.com/gurjeet/pgd).

This directory contains the build output and installation of various branches of
its parent Git directory.

Feel free to remove any of the directories here, but remember that the data
stored in the database under that directory will also be lost.
EOF
}

pgdCMakelistsGenerate()
{
	# When trying to enhance this function to generate CMakeLists.txt for other
	# parts of Postgres (contrib, bin, interfaces) do remember to see the accepted
	# answer to this SO question:
	#
	# http://stackoverflow.com/questions/9673326/cmakelists-txt-files-for-multiple-libraries-and-executables

	# Save stdout in FD 4, and open CMakeLists.txt as stdout
	exec 4<&1
	exec 1>CMakeLists.txt

	echo 'cmake_minimum_required(VERSION 3.2)'
	echo
	echo 'project(Postgres)'

	echo
	echo 'configure_file (
		"${PROJECT_SOURCE_DIR}/src/include/pg_config.h.in"
		"${PROJECT_BINARY_DIR}/src/include/pg_config.h"
		)'

	echo
	echo 'include_directories(Postgres ./src/include)'
	echo 'include_directories("${PROJECT_BINARY_DIR}/src/include")'

	echo
	echo 'set(BACKEND_SOURCE_FILES'

	find src/backend src/common \( -type f -name '*.c' -o -name '*.h' \) -printf '\t%p\n'

	echo ')'

	echo
	echo 'add_executable(postgres ${BACKEND_SOURCE_FILES})'

	# Restore stdout from FD 4
	exec 1<&4
}

# Commented out function; I don't want to make decisions for people. They can
# choose how they want to name their branches. Function wasn't complete, but
# keeping it around in case I want to implement it for private use.
: << 'COMMENT'
pgdBuildStableBranches()
{
	# `git-branch -r` output looks like this:
	#	origin/REL8_1_STABLE
	for branch_name_U in $(git branch -r | grep STABLE | cut -d '/' -f 2 | uniq ); do
		# lower-case the branch name, and replace underscore with dots
		branch_name=$(echo branch_name_U | tr [A-Z_] [a-z.])

		# Replace rel8.1 with pg_8.1
		branch_name=${branch_name/#rel/pg_}

		# Replace edbas9.1 with edb_8.1
		branch_name=${branch_name/#edbas/edb_}

		# Replace trailing .stable with _stable
		branch_name=${branch_name/%.stable/_stable}

		echo Checking out
	done
}
COMMENT

function pgdHookBranchDetectionIntoShell()
{
	echo "$PROMPT_COMMAND" | grep -w pgdDetectBranchChange

	if [[ $? -eq 0 ]]; then
		echo '$PROMPT_COMMAND seems to already contain branch detection code.'
		echo "\$PROMPT_COMMAND=$PROMPT_COMMAND"
		echo 'Skipping.'
		return 0;
	fi

	# Append branch detection code to $PROMPT_COMMAND so that we can detect Git
	# branch change ASAP.
	#
	PROMPT_COMMAND="${PROMPT_COMMAND:-:;}"	# If empty, substitute a no-op
	# If it doesn't end with a semi-colon, append one.
	PROMPT_COMMAND="${PROMPT_COMMAND}$( [[ $(echo -n ${PROMPT_COMMAND} | tail -c 1) == ';' ]] && echo '' || echo ';' )"
	PROMPT_COMMAND=${PROMPT_COMMAND}'pgdDetectBranchChange >/dev/null 2>&1;'
}

# Hook our brach-change-detection code into Bash prompt
pgdHookBranchDetectionIntoShell

# If the script was invoked with some parameters, then assume $1 to be a
# function's name (possibly defined in this file), and pass the rest of the
# arguments to that function.
if [ "x$1" != "x" ] ; then
	command="$1"
	shift
	eval "$command" "$@"
fi
