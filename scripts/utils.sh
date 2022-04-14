# we expect the 'bb' variable to be provided by the script that includes this

isPrivileged() {
	if [ "$privileged" = "" ]; then
		test $($bb id -u) = "0"
	else
		[ "$privileged" = "1" ] && return 0 || return 1
	fi
}

# detects if the path as argument contains a valid jail
isValidJailPath() {
	local jPath=$1
	if [ -d $jPath/root ] \
		&& [ -d $jPath/run ] \
		&& [ -f $jPath/startRoot.sh ] \
		&& [ -f $jPath/rootCustomConfig.sh ] \
		&& [ -x $jPath/root/bin/busybox ]; then
		return 0
	else
		return 1
	fi
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
		| $bb grep "\/root \/ "\
		| $bb sed -e 's/^[0-9]\+ [0-9]\+ [0-9:]\+ \([^ ]*\)\/root \/.*$/\1/')
	echo ${result##$prefix}
	return 0
}

# returns :
#	2 when the file ns.pid contains a wrong process pid (could be after a reboot)
#	1 it is not running
#	0 the jail is running
isJailRunning() {
	local jailPath=$1 # this has to be an absolute path

	getProcessPathFromPwdx() {
		local pidFile=$1
		$bb pwdx $($bb cat $pidFile)\
			| $bb sed -e 's/^[0-9]*: *//' \
			| $bb sed -e 's/\/root$//'
	}

	# the files exist and the size is more than zero
	[ -s $jailPath/run/jail.pid ] && [ -s $jailPath/run/ns.pid ] || return 1

	getProcessPathFromPwdx $jailPath/run/ns.pid | $bb grep -q "^$jailPath$" && return 0
	getProcessPathFromPwdx $jailPath/run/jail.pid | $bb grep -q "^$jailPath$" && return 0

	local nsPid=$(cat $jailPath/run/ns.pid)
	local err=0

	# check that the process is running correctly
	$bb ps | $bb grep -q "^ *$nsPid " || err=1

	[ "$err" = "0" ] && isValidJailPath "$(getProcessPathFromMountinfo $nsPid)" && return 0 || err=1

	if [ "$err" = "1" ]; then
		echo "The jail's pid doesn't seem to be correct, it should be deleted" >&2
		return 2
	fi
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

listAllPidsOwnedByUser() {
	user=$1
	for pid in $($bb ps | $bb grep "[0-9]\+ $user" \
		| $bb sed -e 's/\([0-9]\+\).*/\1/'); do
		[ "$($bb readlink /proc/$pid/ns/pid)" != "$($bb readlink /proc/$$/ns/pid)" ] && echo $pid
	done
}

listJails() {
	local jailName=$1

	prefix=$(getProcessPathFromMountinfo 1)
	[ "$prefix" = "/" ] && prefix="" || prefix="$prefix/root"

	if [ "$jailName" != "" ]; then # user asked for a specific jail

		if printf "%s" "$jailName" | $bb grep -q '^\/'; then
			jailName="^$jailName$"
		else
			jailName="\/$jailName$"
		fi

		first=true
		for pid in $(listAllPidsOwnedByUser $(id -un)); do
			dPath=$(getProcessPathFromMountinfo $pid $prefix) || continue
			if isValidJailPath $dPath; then
				if echo $dPath | $bb grep -q $jailName; then
					if [ "$first" = "true" ]; then
						printf "jail path : $dPath\npids :\n"
						first=false
					fi
					echo $pid
				fi
			fi
		done
	else # output all jails
		for pid in $(listAllPidsOwnedByUser $(id -un)); do
			dPath=$(getProcessPathFromMountinfo $pid $prefix) || continue
			isValidJailPath $dPath && echo "$dPath - pid $pid"
		done
	fi
}

listJailsMain() {
	result=$(callGetopt "list [jail name]" \
		-o '' '' "" "jailName" "true" \
		-- "$@")

	if [ "$?" = "0" ]; then
		if jailName=$(getVarVal 'jailName' "$result"); then
			listJails $jailName
		else
			listJails | $bb sort
		fi
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
