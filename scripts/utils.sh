# Miscellaneous functions library used by most other modules.
#
# direct call :
# jt --run jt_utils
#
# we expect the 'bb' variable to be provided by the script that includes this

isPrivileged() {
	# privileged is a potentially global variable set by jailLib
	if [ "$privileged" = "" ]; then
		test $($bb id -u) = "0"
	else
		[ "$privileged" = "1" ] && return 0 || return 1
	fi
}

getBaseUserUID() {
	local rootDir=$1
	$bb stat -c %u $rootDir/rootDefaultConfig.sh
}

getBaseUserGID() {
	local rootDir=$1
	$bb stat -c %g $rootDir/rootDefaultConfig.sh
}

getActualUser() {
	local rootDir=$1
	$bb stat -c %U $rootDir/rootDefaultConfig.sh
}

getBaseUserCredentials() {
	local rootDir=$1
	echo "$(getBaseUserUID $rootDir):$(getBaseUserGID $rootDir)"
}

getUtime() {
	local raw=$($bb adjtimex)

	local seconds=$(printf "%s" "$raw" | $bb sed -ne '/time.tv_sec/ {s/[^0-9]//g ; p}')
	local microseconds=$(printf "%s" "$raw" | $bb sed -ne '/time.tv_usec/ {s/[^0-9]//g ; p}')

	echo ${seconds}.$microseconds
}

# detects if the path as argument contains a valid jail
isValidJailPath() {
	local jPath=$1
	if [ -d $jPath ] && [ -d $jPath/root ] \
		&& [ -d $jPath/run ] \
		&& [ -f $jPath/rootDefaultConfig.sh ] \
		&& [ -f $jPath/rootCustomConfig.sh ] \
		&& [ -f $jPath/._rootCustomConfig.sh.initial ] \
		&& [ -x $jPath/root/bin/busybox ]; then
		return 0
	else
		return 1
	fi
}

# this runs the script in the path first
# if not available, it runs the script using
# the runner (embedded). This function will block so you will
# have to call it in another thread.
# this cats either the local file first and if not available
# the embedded file to a fifo which is created by this function.
# Callers can then run the prepared script by doing :
#	$bb sh $rootDir/run/instrFile <arguments>
#	(here 'instrFile' is the FIFO file)
prepareScriptInFifo() {
	local fifoPath=$1
	local localFilename=$2
	local embedFilename=$3
	
	if [ ! -d $($bb dirname $fifoPath) ]; then
		echo "Error - prepareScriptInFifo - Provided path is not valid" >&2
		return 1
	fi

	if [ -p $fifoPath ]; then
		echo "Error - prepareScriptInFifo - FIFO file already exists, bailing out" >&2
		return 1
	else
		$bb mkfifo $fifoPath
		$bb chmod 700 $fifoPath
		if [ "$localFilename" != "" ] && [ -r $localFilename ]; then
			$bb cat $localFilename > $fifoPath
		else
			$JT_SHOWER $embedFilename > $fifoPath
		fi
		# fifo are a one-shot deal anyway, at least the way we use them
		rm $fifoPath
	fi
	return 0
}

getProcessPathFromEnviron() {
	local pid=$1
	local prefix=$2
	[ ! -d /proc ] || [ ! -d /proc/$pid ] || [ ! -e /proc/$pid/environ ] && return 1

	local result=$($bb cat /proc/$pid/environ | $bb sed -e 's/\x00/\n/g' | $bb grep '^JT_LOCATION' | $bb sed -e 's/JT_LOCATION=//')
	[ "$result" != "" ] && echo ${result##$prefix} || return 1
	return 0
}

getProcessPathFromMountinfo() {
	local pid=$1
	local prefix=$2
	[ ! -d /proc ] || [ ! -d /proc/$pid ] || [ ! -e /proc/$pid/mountinfo ] && return 1
	# in case mountinfo is empty, we bail out with an error
	# can't use test -s on that file for some reasons
	$bb cat /proc/$pid/mountinfo | $bb wc -c | $bb grep -q '^0$' && return 1
	# we filter a line similar to this :
	# 150 138 179:2 /home/user/somePath/someJail/root / rw,relatime - ext4 /dev/root rw
	local result=$($bb cat /proc/$pid/mountinfo\
		| $bb grep "\/root\(\|\/\/deleted\) \/ "\
		| $bb sed -e 's/^[0-9]\+ [0-9]\+ [0-9:]\+ \([^ ]*\)\/root\(\|\/\/deleted\) \/.*$/\1/')
	[ "$result" != "" ] && echo ${result##$prefix} || return 1
	return 0
}

isProcessAValidJail() {
	local pid=$1

	$bb cat /proc/$pid/environ 2>/dev/null | $bb grep "JT_VERSION" >/dev/null || return 1

	return 0
}

getProcessPathFromPwdx() {
	local pid=$1
	$bb pwdx $pid\
		| $bb sed -e 's/^[0-9]*: *//' \
		| $bb sed -e 's/\/root$//'
}

isProcessRunning() {
	local pid=$1

	$bb ps | $bb grep -q "^$pid *[^ ]\+ *[0-9]\+ *[^ ]* *sh -c while :; do /bin/busybox sleep 9999; done"
}

# this is specifically when we absolutely know the jail's inner core process id like what we get
# from 'run/ns.pid'
isJailRunning() {
	local jailPath=$1 # this has to be an absolute path

	# the files exist and the size is more than zero
	[ -s $jailPath/run/jail.pid ] && [ -s $jailPath/run/ns.pid ] || return 1
	local nsPid=$($bb cat $jailPath/run/ns.pid)
	local jailPid=$($bb cat $jailPath/run/jail.pid)

	if ! $bb ps | $bb grep -q "^ *$nsPid "; then
		return 1
	fi

	getProcessPathFromPwdx $nsPid | $bb grep -q "^$jailPath$" && return 0
	getProcessPathFromPwdx $jailPid | $bb grep -q "^$jailPath$" && return 0

	isProcessRunning $nsPid || return 1
	isValidJailPath "$(getProcessPathFromEnviron $nsPid)" || return 1
}

stripQuotes() {
	$bb sed -e 's/"//g' -e 's/\x27//g'
}

# substring offset <optional length> string
# cuts a string at the starting offset and wanted length.
substring() {
        local init=$1
	shift

        if [ "$2" != "" ]; then
		toFetch="\(.\{$1\}\).*"
		shift
	else
		local toFetch="\(.*\)"
	fi

        echo "$1" | $bb sed -e "s/^.\{$init\}$toFetch$/\1/"
}

# arguments : <input file> [<to replace string> <replacement string>, ...]
populateFile() {
	local inFile=$1
	shift
	local result=""

	while [ "$1" != "" ] && [ "$2" != "" ]; do
		result="$result s%$1%$2%g;"
		shift 2
	done

	$bb cat $inFile | $bb sed -e "$result"
}

waitUntilFileAppears() {
	local eventFile="$1"
	local endTime="$(($($bb date +"%s") + $2))"
	local noDelete="$3"

	while [ ! -e $eventFile ]; do
		if [ $(($($bb date +"%s") >= $endTime )) = 1 ]; then
			return 1
		fi
		$bb sleep 0.1
	done
	[ "$noDelete" = "0" ] && $bb rm $eventFile
	return 0
}

listAllNamespacedPidsOwnedByUser() {
	user=$1
	for pid in $($bb ps | $bb grep "[0-9]\+ $user" \
		| $bb sed -e 's/\([0-9]\+\).*/\1/'); do
		[ "$($bb readlink /proc/$pid/ns/pid)" != "" ] && [ "$($bb readlink /proc/$pid/ns/pid)" != "$($bb readlink /proc/$$/ns/pid)" ] && echo $pid
	done
}

listAllJails() {
	OPTIND=0
	local showZombies="false"
	local showJailPath="true"
	local showPrettyPrint="true"
	local showPid="true"
	while getopts rz f 2>/dev/null ; do
		case $f in
			r) showPrettyPrint="false";;
			z) showZombies="true"; showJailPath="false"; showPrettyPrint="false";;
		esac
	done
	[ $(($OPTIND > 1)) = 1 ] && shift $($bb expr $OPTIND - 1)
	local user=$1

	local prefix=$(getProcessPathFromMountinfo 1)
	[ "$prefix" = "/" ] && prefix="" || prefix="$prefix/root"

	showResult() {
		jailPath=$1
		pid=$2
		[ "$showJailPath" = "true" ] && printf "$jailPath "
		[ "$showPrettyPrint" = "true" ] && printf "- pid "
		[ "$showPid" = "true" ] && printf "$pid"
		printf "\n"
	}

	local allegedlyJailPath=""
	for pid in $(listAllNamespacedPidsOwnedByUser $user); do
		if [ "$pid" = "1" ] || $bb pgrep -P 1 | $bb grep -q $pid; then
			# in case we are in a jail, these may be detected as a zombie jail
			continue
		fi

		allegedlyJailPath=$(getProcessPathFromMountinfo $pid $prefix)
		if [ "$?" != "0" ]; then
			if isProcessAValidJail $pid; then
				allegedlyJailPath=" "
			else
				continue
			fi
		fi

		if isValidJailPath $allegedlyJailPath && isJailRunning $allegedlyJailPath; then
			[ "$showZombies" = "false" ] && showResult "$allegedlyJailPath" $pid
		else
			[ "$showZombies" = "true" ] && showResult "$allegedlyJailPath" $pid
		fi
	done
}

listSpecificJail() {
	local user=$1
	local jailName=$2

	if printf "%s" "$jailName" | $bb grep -q '^\/'; then
		jailName="^$jailName$"
	else
		jailName="\/$jailName "
	fi

	local entries=$(listAllJails -r $user | $bb grep $jailName)
	local first=true
	oldIFS=$IFS
	IFS="
"
	for entry in $entries; do
		IFS=$oldIFS
		set -- $entry
		jailPath=$1
		pid=$2
		if [ "$first" = "true" ]; then
			printf "jail path : $jailPath\npids :\n"
			first=false
		fi
		echo $pid
	done
	IFS=$oldIFS
}

listJailsMain() {
	local result=""
	result=$(callGetopt "list [jail name]" \
		-o 'z' '' "list only zombie processes (running jails that no longer have a directory presence)" "listZombies" "false" \
		-o '' '' "" "jailName" "true" \
		-- "$@")
	local err=$?

	local args=""
	getVarVal 'listZombies' "$result" >/dev/null && args="-z"

	if [ "$err" = "0" ]; then
		if jailName=$(getVarVal 'jailName' "$result"); then
			[ "$jailName" != "" ] && listSpecificJail $($bb id -un) $jailName
		else
			listAllJails $args $($bb id -un) | $bb sort
		fi
	fi
}

# mkdir -p with a mode only applies the mode to the last child dir... this function applies the mode to all directories
# arguments :
#		-m [directory permission mode in octal]
#		-e (this makes the function output the commands rather than apply them directly)
cmkdir() {
	OPTIND=0
	local callArgs=""
	local arguments=""
	local isOutput="false" # we will output the commands rather than apply them
	local result=""
	while getopts m:e f 2>/dev/null; do
		case $f in
			m) callArgs="$callArgs --mode=$OPTARG";;
			e) isOutput="true";;
		esac
	done
	[ $(($OPTIND > 1)) = 1 ] && shift $($bb expr $OPTIND - 1)
	arguments="$@"

	for dir in $(echo $arguments); do
		local subdirs="$(echo $dir | $bb sed -e 's/\//\n/g')"
		if [ "$(substring 0 1 $dir)" = "/" ]; then # checking for an absolute path
			local parentdir="/"
		else # relative path
	                local parentdir=""
		fi
		for subdir in $(echo $subdirs); do
			if [ "$isOutput" = "false" ]; then
				if test ! -d $parentdir$subdir; then
					$bb mkdir $callArgs $parentdir$subdir
					isPrivileged && $bb chown $actualUser $parentdir$subdir
				fi
			else
				result="$result $bb mkdir -p $callArgs $parentdir$subdir;"
			fi

			if [ "$parentdir" = "" ]; then
				local parentdir="$subdir/"
			else
				local parentdir="$parentdir$subdir/"
			fi
		done
	done

	if [ "$isOutput" = "true" ]; then
		echo $result
	fi
}

getConfigValue() {
	local configPath=$1
	local configName=$2

	$bb cat $configPath | $bb sed -e "s/^$configName=\(.*\)$/\1/"
}

getVarVal() {
	local var="$1"
	shift

	oldIFS=$IFS
	IFS=";"
	for i in $@; do
		IFS="="
		set -- $i
		IFS=$oldIFS
		if [ "$1" = "$var" ]; then # booleans are handled differently, they will also return a value to make their use more intuitive
			#([ "$2" != "\"\"" ] && [ "$2" != "\"0\"" ]) && echo $2 | sed -e 's/"//g' && return 0 || return 1
			# we remove only the front and last double quotes
			([ "$2" != "\"\"" ] && [ "$2" != "\"0\"" ]) && echo $2 | $bb sed -e 's/^"\(.*\)"$/\1/' | $bb sed -e 's/%3D/=/g' && return 0 || return 1
		fi
	done
	return 2 # we found no argument by this name
}

# return 0 on normal with variables
# return 1 on error
# return 2 on show help message
callGetopt() {
	[ "$#" = "0" ] && return 1
	local headerMessage="$1"
	shift
	local smallOpt=""
	local longOpt=""
	local caseCond=""
	local result=""

	local help="$headerMessage"

	set -- '-o' 'h' 'help' 'display this help' '' 'false' "$@"
	while true; do
		case $1 in
			-o|--option)
				shift
				availableShortOptions=$1
				availableLongOptions=$2
				optionDescription=$3
				optionResultVariable=$4
				isExpectingArgument=$5
				shift 4

				if [ "$optionResultVariable" != "" ]; then
					if [ "$isExpectingArgument" = "true" ]; then
						[ "$result" = "" ] && result="$optionResultVariable=\"\"" || result="${result};$optionResultVariable=\"\""
					else
						[ "$result" = "" ] && result="$optionResultVariable=\"0\"" || result="${result};$optionResultVariable=\"0\""
					fi
				fi

				sC=""; [ "$availableShortOptions" != "" ] && sC="-$availableShortOptions"
				lC=""; [ "$availableLongOptions" != "" ] && lC="--$availableLongOptions"

				if [ "$optionDescription" != "" ]; then
					if [ "$availableShortOptions" != "" ] && [ "$availableLongOptions" != "" ]; then
						[ "$isExpectingArgument" = "true" ] && help="$help\n\t$sC INPUT, $lC=INPUT\t\t\t$optionDescription" || help="$help\n\t$sC, $lC\t\t\t$optionDescription"
					elif [ "$availableShortOptions" != "" ]; then
						[ "$isExpectingArgument" = "true" ] && help="$help\n\t$sC INPUT\t\t\t$optionDescription" || help="$help\n\t$sC\t\t\t$optionDescription"
					else
						[ "$isExpectingArgument" = "true" ] && help="$help\n\t$lC=INPUT\t\t\t$optionDescription" || help="$help\n\t$lC\t\t\t$optionDescription"
					fi
				fi

				[ "$caseCond" = "" ] && caseCond="$sC,$lC,$optionResultVariable,$isExpectingArgument" || caseCond="$caseCond:$sC,$lC,$optionResultVariable,$isExpectingArgument"

				if [ "$isExpectingArgument" = "true" ]; then
					[ "$availableShortOptions" != "" ] && availableShortOptions="$availableShortOptions:"
					[ "$availableLongOptions" != "" ] && availableLongOptions="$availableLongOptions:"
				fi

				[ "$availableShortOptions" != "" ] && smallOpt="${smallOpt}$availableShortOptions"
				if [ "$availableLongOptions" != "" ]; then
					[ "$longOpt" = "" ] && longOpt="$availableLongOptions" || longOpt="$longOpt,$availableLongOptions"
				fi
			;;
			--) break;;
			*) break;;
		esac
		shift
	done

	[ "$#" != "0" ] && [ "$1" = "--" ] && shift # we get rid of '--'

	O=$($bb getopt -l $longOpt $smallOpt "$@") || return 1

	eval set -- $O

	handleOpts() {
		local in="$(printf "%s" "$1" | $bb sed -e 's/\//%2f/g' | $bb sed -e 's/;/%3B/g' | $bb sed -e 's/\=/%3D/g')"	# the input argument to parse
		local arg="$(printf "%s" "$2" | $bb sed -e 's/\x27//g' | $bb sed -e 's/\=/%3D/g')"	# the second argument if any
		local caseConditionals="$3"	# we have to check the inputs against these to find the target arguments
		local helpMessage="$4"		# the help message
		local rs="$5"			# the result variable
		# add single quotes to content with spaces
		echo "$in" | $bb grep -q '\( \|%20\)' && in="$(echo "$in" | $bb sed -e "s/\(.*\)/'\1'/")"
		oldIFS="$IFS"
		IFS=":"
		for rawCond in $caseConditionals; do
			IFS=","
			set -- $rawCond # we change the positional parameters to split the content of rawCond
			IFS="$oldIFS"
			sC=$1		# short conditional
			lC=$2		# long conditional
			v=$3		# output variable name
			hasArg=$4	# has argument boolean

			[ "$in" = "--" ] && echo $rs && return 0
			[ "$in" = "" ] && echo $rs && return 4

			if [ "$in" = "-h" ] || [ "$in" = "--help" ]; then
				printf "$helpMessage\n\n" >&2
				return 2
			fi

			if [ "$in" = "$sC" ] || [ "$in" = "$lC" ]; then
				if [ "$hasArg" = "true" ]; then
					echo $(printf "%s" "$rs" | $bb sed -e "s/$v=\"\"/$v=\"$arg\"/")
					return 3
				else
					echo $(printf "%s" "$rs" | $bb sed -e "s/$v=\"0\"/$v=\"1\"/")
					return 0
				fi
			elif [ "$sC" = "" ] && [ "$lC" = "" ]; then
				if [ "$hasArg" = "true" ] && printf "%s" "$rs" | $bb grep -q "$v=\"\""; then
					echo $(printf "%s" "$rs" | $bb sed -e "s/$v=\"\"/$v=\"$in\"/" | $bb sed -e 's/%2f/\//g' -e 's/%20/ /g')
					return 0
				fi
			fi
		done
		# this is the catchall on the last flagless argument
		if [ "$sC" = "" ] && [ "$lC" = "" ]; then
			if [ "$hasArg" = "true" ]; then
				echo $(printf "%s" "$rs" | $bb sed -e "s/$v=\"\(.*\)\"/$v=\"\1 $in\"/" | $bb sed -e 's/%2f/\//g' -e 's/%20/ /g')
				return 0
			fi
		fi

		echo $rs
	}

	while true; do
		result=$(handleOpts "$1" "$2" "$caseCond" "$help" "$result")
		case $? in
			0):;;
			1)return 1;;
			2)return 2;;
			3)shift;;
			4)echo $result; return 0;;
		esac
		shift
	done
}

# example usage of callGetopt

#meinResult=$(callGetopt "status [OPTIONS] <argument 1> <argument 2>" \
#       -o "i" "" "display ip information" "showIp" "false" \
#       -o "" "ps" "display process information" "showProcessStats" "false" \
#       -o "o" "output" "some output needs an input" "outputData" "true" \
#       -o '' '' "" "arg1Data" "true" \
#       -o '' '' "" "arg2Data" "true" \
#       -- "$@")
#err=$?

#if [ "$err" = "0" ]; then
#	if getVarVal 'showProcessStats' "$meinResult" >/dev/null; then
#		ps
#	elif getVarVal 'showIp' "$meinResult" >/dev/null; then
#		/sbin/ip addr
#	elif outputData=$(getVarVal 'outputData' "$meinResult"); then
#		echo $outputData
#	fi
#
#	if arg1Data=$(getVarVal 'arg1Data' "$meinResult"); then
#		echo "arg1 Data : $arg1Data"
#	fi
#	if arg2Data=$(getVarVal 'arg2Data' "$meinResult"); then
#		echo "arg2 Data : $arg2Data"
#	fi
#fi

if [ "$IS_RUNNING" = "1" ]; then
	if [ "$1" = "" ]; then
		exit
	fi
	cmd=$1
	shift

	case $cmd in
		*)
			$cmd "$@"
		;;
	esac
fi
