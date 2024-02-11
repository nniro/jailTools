#! @SHELL@
# Don't change anything in this script! Use rootCustomConfig.sh for your changes!

bb="$BB"
shower="$JT_SHOWER"
runner="$JT_RUNNER"

if [ "$bb" = "" ] || [ "$shower" = "" ] || [ "$runner" = "" ]; then
	echo "It is no longer possible to run this script directly. The 'jt' command has to be used."
	exit 1
fi

ownPath=$($bb dirname $0)


if [ "$ownPath" = "." ]; then
	ownPath=$PWD
else
	if echo $ownPath | grep -q '^\/'; then
		# absolute path, we do nothing
		:
	else
		# relative path
		ownPath=$PWD/$ownPath
	fi
fi

. $ownPath/jailLib.sh

prepareCmd() {
	local env="$1"
	local cmd="$2"
	shift 2
	local result=

	if [ "$1" != "" ]; then
		result="busybox env $env $@"
	else
		if [ "$cmd" = "" ]; then
			result="busybox env $env sh"
		else
			result="busybox env $env $cmd"
		fi
	fi

	#echo $result >&2
	echo $result
}

getRunEnvironment() {
	local ownPath=$1

	local vars=$(getCurVal $ownPath runEnvironment | $bb sed -e 's/ /\n/g' | $bb sed -e 's/.*\(\$[^ ]\+\)/\1 /' | $bb sed -e 's/^\$//')

	local regexResult=""
	for var in $vars; do
		if [ "$var" = "userUID" ]; then
			regexResult="$regexResult s/\\\\\$$var/$(getBaseUserUID $ownPath)/ ;"
		elif [ "$var" = "actualUser" ]; then
			regexResult="$regexResult s/\\\\\$$var/$(getActualUser $ownPath)/ ;"
		elif [ "$var" = "userGID" ]; then
			regexResult="$regexResult s/\\\\\$$var/$(getBaseUserGID $ownPath)/ ;"
		else
			regexResult="$regexResult s/\\\\\$$var/$($bb env | $bb sed -ne "/^${var}=/ {s/^${var}=\(.\+\)$/\1 / ; p; q}")/ ;"
		fi
	done

	getCurVal $ownPath runEnvironment | $bb sed -e "$regexResult"
}

showHelp() {
	echo "startRoot <Jail PATH> <start|stop|shell|daemon>"
}

cmdParse() {
	local ownPath=$1
	local args=$2
	local err=0

	if [ "$args" = "" ]; then
		showHelp
		exit 1
	fi
	shift 2

	case $args in
		daemon)
			echo "This command is not meant to be called directly, use the jailtools super script to start the daemon properly, otherwise it will just stay running with no interactivity possible." >&2
			prepareChroot $ownPath || exit 1
			runShell -pd $ownPath $($bb cat $ownPath/run/ns.pid) $(prepareCmd "$(getRunEnvironment $ownPath)" "$(getCurVal $ownPath daemonCommand)" "$@")
			err=$?
			stopChroot $ownPath
			exit $err
		;;

		start)
			prepareChroot $ownPath || exit 1
			runShell -p $ownPath $($bb cat $ownPath/run/ns.pid) $(prepareCmd "$(getRunEnvironment $ownPath)" "$(getCurVal $ownPath startCommand)" "$@")
			err=$?
			stopChroot $ownPath
			exit $err
		;;

		stop)
			stopChroot $ownPath
			exit $?
		;;

		shell)
			if [ -e $ownPath/run/ns.pid ]; then
				local nsPid=$(cat $ownPath/run/ns.pid)
			
				if [ "$privileged" = "1" ]; then
					echo "Entering the already started jail \`$(getCurVal $ownPath jailName)'" >&2
				else
					echo "Entering the already started jail \`$(getCurVal $ownPath jailName)' unprivileged)" >&2
				fi
				[ "$nsPid" = "" ] && (echo "Unable to get the running namespace, bailing out" && exit 1)
				runShell $ownPath $nsPid $(prepareCmd "$(getRunEnvironment $ownPath)" "$(getCurVal $ownPath shellCommand)" "$@")
				exit $?
			else # we start a new jail
				echo "This jail is not started, please start it with the \"daemon\" command" >&2
				exit 1
			fi
		;;

		*)
			showHelp
			exit 1
		;;
	esac
}

case $1 in

	*)
		if [ "$1" = "" ]; then
			s1="."
		else
			s1=$1
			shift
		fi

		cmdParse $ownPath $s1 "$@"
	;;
esac
