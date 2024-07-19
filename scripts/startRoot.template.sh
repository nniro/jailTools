#! @SHELL@
# Don't change anything in this script! Use rootCustomConfig.sh for your changes!
#
# Jail management script.
#
# direct call :
# jt --run jt_startRoot_template

bb="$BB"
shower="$JT_SHOWER"
runner="$JT_RUNNER"

if [ "$bb" = "" ] || [ "$shower" = "" ] || [ "$runner" = "" ]; then
	echo "It is no longer possible to run this script directly. The 'jt' command has to be used."
	exit 1
fi

if [ "$IS_RUNNING" = "1" ]; then
	IS_RUNNING=0
fi

ownPath=$1

if [ "$ownPath" = "" ] || [ ! -d $ownPath ]; then
	echo "First argument must be the directory path of the jail" >&2
	exit 1
fi
shift


cConfig() {
	bb=$bb $runner jt_config "$@"
}

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

	local vars=$(cConfig getCurVal $ownPath runEnvironment | $bb sed -e 's/ /\n/g' | $bb sed -e 's/.*\(\$[^ ]\+\)/\1 /' | $bb sed -e 's/^\$//')

	local regexResult=""
	for var in $vars; do
		if [ "$var" = "userUID" ]; then
			regexResult="$regexResult s/\\\\\$$var/$(bb=$bb $runner jt_utils getBaseUserUID $ownPath)/ ;"
		elif [ "$var" = "actualUser" ]; then
			regexResult="$regexResult s/\\\\\$$var/$(bb=$bb $runner jt_utils getActualUser $ownPath)/ ;"
		elif [ "$var" = "userGID" ]; then
			regexResult="$regexResult s/\\\\\$$var/$(bb=$bb $runner jt_utils getBaseUserGID $ownPath)/ ;"
		else
			regexResult="$regexResult s/\\\\\$$var/$($bb env | $bb sed -ne "/^${var}=/ {s/^${var}=\(.\+\)$/\1 / ; p; q}")/ ;"
		fi
	done

	cConfig getCurVal $ownPath runEnvironment | $bb sed -e "$regexResult"
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

	bb=$bb $runner jt_utils prepareScriptInFifo $ownPath instrFileStartRoot "jailLib.sh" "jt_jailLib_template" &
	if ! bb=$bb $runner jt_utils waitUntilFileAppears "$ownPath/run/instrFileStartRoot" 2 1; then
		echo "StartRoot - Timed out waiting for FIFO to be created" >&2
		exit 1
	fi

	. $ownPath/run/instrFileStartRoot
	$bb rm $ownPath/run/instrFileStartRoot

	case $args in
		daemon)
			echo "This command is not meant to be called directly, use the jailtools super script to start the daemon properly, otherwise it will just stay running with no interactivity possible." >&2
			prepareChroot $ownPath || exit 1
			runShell -pd $ownPath $($bb cat $ownPath/run/ns.pid) $(prepareCmd "$(getRunEnvironment $ownPath)" "$(cConfig getCurVal $ownPath daemonCommand)" "$@")
			err=$?
			stopChroot $ownPath
			exit $err
		;;

		start)
			prepareChroot $ownPath || exit 1
			runShell -p $ownPath $($bb cat $ownPath/run/ns.pid) $(prepareCmd "$(getRunEnvironment $ownPath)" "$(cConfig getCurVal $ownPath startCommand)" "$@")
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
			
				if bb=$bb $runner jt_utils isPrivileged; then
					echo "Entering the already started jail \`$(cConfig getCurVal $ownPath jailName)'" >&2
				else
					echo "Entering the already started jail \`$(cConfig getCurVal $ownPath jailName)' unprivileged" >&2
				fi
				[ "$nsPid" = "" ] && (echo "Unable to get the running namespace, bailing out" && exit 1)
				runShell $ownPath $nsPid $(prepareCmd "$(getRunEnvironment $ownPath)" "$(cConfig getCurVal $ownPath shellCommand)" "$@")
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

cmdParse $ownPath "$@"
