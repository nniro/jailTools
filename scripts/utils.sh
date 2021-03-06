#! /bin/sh

# we expect the 'bb' variable to be provided by the script that includes this

# detects if the path as argument contains a valid jail
detectJail() {
	local jPath=$1
	if [ -d $jPath/root ] && [ -d $jPath/run ] && [ -f $jPath/startRoot.sh ] && [ -f $jPath/rootCustomConfig.sh ]; then
		return 0
	else
		return 1
	fi
}

# returns :
#	1 the jail is running
#	0 it is not running
#	-1 when the file ns.pid contains a wrong process pid (could be after a reboot)
jailStatus() {
	local jailPath=$1 # this has to be an absolute path

	local running=0

	if [ -e $jailPath/run/ns.pid ]; then
		local pPath=$($bb pwdx $(cat $jailPath/run/ns.pid) | $bb sed -e 's/^[0-9]*: *//')

		if [ "$jailPath/root" = "$pPath" ]; then
			running=1
		else
			echo "The jail's pid doesn't seem to be correct, it should be deleted" >&2
			running=-1
		fi
	fi

	echo $running
}

# substring offset <optional length> string
# cuts a string at the starting offset and wanted length.
substring() {
        local init=$1; shift
        if [ "$2" != "" ]; then toFetch="\(.\{$1\}\).*"; shift; else local toFetch="\(.*\)"; fi
        echo "$1" | sed -e "s/^.\{$init\}$toFetch$/\1/"
}

# arguments : <input file> [<to replace string> <replacement string>, ...]
populateFile() {
	local inFile=$1
	shift
	local result=""

	while [ "$1" != "" ] && [ "$2" != "" ]; do
		result="$result s%$1$%$2%g;"
		shift 2
	done

	cat $inFile | sed -e "$result"
}

getConfigValue() {
	local configPath=$1
	local configName=$2

	cat $configPath | sed -e "s/^$configName=\(.*\)$/\1/"
}

getVarVal() {
	local var="$1"
	shift

	IFS=";"
	for i in $@; do
		oldIFS=$IFS; IFS="="
		set -- $i; IFS=$oldIFS
		if [ "$1" = "$var" ]; then # booleans are handled differently, they will also return a value to make their use more intuitive
			([ "$2" != "\"\"" ] && [ "$2" != "\"0\"" ]) && echo $2 | sed -e 's/"//g' && return 0 || return 1
		fi
	done
	return 2 # we found no argument by this name
}

# return 0 on normal with variables
# return 1 on error
# return 2 on show help message
callGetopt() {
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
				s=$1		# short option
				l=$2		# long option
				msg=$3		# help message
				vval=$4		# variable to save the result value to
				hasArg=$5	# are we expecting an argument or just a flag
				shift 4

				if [ "$vval" != "" ]; then
					if [ "$hasArg" = "true" ]; then
						[ "$result" = "" ] && result="$vval=\"\"" || result="${result};$vval=\"\""
					else
						[ "$result" = "" ] && result="$vval=\"0\"" || result="${result};$vval=\"0\""
					fi
				fi

				sC=""; [ "$s" != "" ] && sC="-$s"
				lC=""; [ "$l" != "" ] && lC="--$l"

				if [ "$msg" != "" ]; then
					if [ "$s" != "" ] && [ "$l" != "" ]; then
						[ "$hasArg" = "true" ] && help="$help\n\t$sC INPUT, $lC=INPUT\t\t\t$msg" || help="$help\n\t$sC, $lC\t\t\t$msg"
					elif [ "$s" != "" ]; then
						[ "$hasArg" = "true" ] && help="$help\n\t$sC INPUT\t\t\t$msg" || help="$help\n\t$sC\t\t\t$msg"
					else
						[ "$hasArg" = "true" ] && help="$help\n\t$lC=INPUT\t\t\t$msg" || help="$help\n\t$lC\t\t\t$msg"
					fi
				fi

				[ "$caseCond" = "" ] && caseCond="$sC,$lC,$vval,$hasArg" || caseCond="$caseCond:$sC,$lC,$vval,$hasArg"

				if [ "$hasArg" = "true" ]; then
					[ "$s" != "" ] && s="$s:"
					[ "$l" != "" ] && l="$l:"
				fi

				[ "$s" != "" ] && smallOpt="${smallOpt}$s"
				if [ "$l" != "" ]; then
					[ "$longOpt" = "" ] && longOpt="$l" || longOpt="$longOpt,$l"
				fi
			;;
			--) break;;
			*) break;;
		esac
		shift
	done

	shift # we get rid of '--'

	$bb getopt -l $longOpt $smallOpt "$@" >/dev/null || return 1

	set -- "$@"

	handleOpts() {
		local in="$1"			# the input argument to parse
		local arg="$2"			# the second argument if any
		local caseConditionals="$3"	# we have to check the inputs against these to find the target arguments
		local helpMessage="$4"		# the help message
		local rs="$5"			# the result variable
		oldIFS=$IFS
		IFS=":"
		for rawCond in $caseConditionals; do
			IFS=","; set -- $rawCond; IFS=$oldIFS # we change the positional parameters to split the content of rawCond
			sC=$1		# short conditional
			lC=$2		# long conditional
			v=$3		# output variable name
			hasArg=$4	# has argument boolean

			[ "$in" = "--" ] && echo $rs && return 0
			[ "$in" = "" ] && echo $rs && return 4

			if [ "$in" = "$sC" ] || [ "$in" = "$lC" ]; then
				if [ "$sC" = "-h" ]; then
					printf "$helpMessage\n\n" >&2
					return 2
				else
					if [ "$hasArg" = "true" ]; then
						echo $(printf "$rs" | $bb sed -e "s/$v=\"\"/$v=\"$arg\"/")
						return 3
					else
						echo $(printf "$rs" | $bb sed -e "s/$v=\"0\"/$v=\"1\"/")
						return 0
					fi
				fi
			elif [ "$sC" = "" ] && [ "$lC" = "" ]; then
				if [ "$hasArg" = "true" ] && printf "$rs" | grep -q "$v=\"\""; then
					echo $(printf "$rs" | $bb sed -e "s/$v=\"\"/$v=\"$in\"/")
					return 0
				fi
			fi
		done

		echo $rs
	}

	while true; do
		IFS=":"
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
