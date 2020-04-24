#! @SHELL@
# Don't change anything in this script! Use rootCustomConfig.sh for your changes!

bb=@BUSYBOXPATH@

# substring offset <optional length> string
# cuts a string at the starting offset and wanted length.
substring() {
        local init=$1; shift
        if [ "$2" != "" ]; then toFetch="\(.\{$1\}\).*"; shift; else local toFetch="\(.*\)"; fi
        echo "$1" | $bb sed -e "s/^.\{$init\}$toFetch$/\1/"
}

if [ "$ownPath" = "." ]; then
	ownPath=$PWD
else
	if [ "$(substring 0 1 $ownPath)" = "/" ]; then
		# absolute path, we do nothing
		:
	else
		# relative path
		ownPath=$PWD/$ownPath
	fi
fi

. $ownPath/jailLib.sh

prepareCmd() {
	local env=$1
	local cmd=$2
	local result=

	if [ "$cmd" = "" ]; then
		result="$env sh"
	else
		result="$env $cmd"
	fi

	#echo $result >&2
	echo $result
}

cmdParse() {
	local args=$1
	local ownPath=$2
	shift 2
	local err=0

	case $args in
		daemon)
			echo "This command is not meant to be called directly, use the jailtools super script to start the daemon properly, otherwise it will just stay running with no interactivity possible."
			prepareChroot $ownPath || exit 1
			runJail -d $ownPath $(prepareCmd "$runEnvironment" "$daemonCommand")
			err=$?
			stopChroot $ownPath
			exit $err
		;;

		start)
			prepareChroot $ownPath || exit 1
			runJail $ownPath $(prepareCmd "$runEnvironment" "$startCommand") $@
			err=$?
			stopChroot $ownPath
			exit $err
		;;

		stop)
			stopChroot $ownPath
			exit $?
		;;

		shell)
			prepareChroot $ownPath >/dev/null 2>/dev/null
			if [ "$?" != "0" ]; then
				local nsPid=$(cat $ownPath/run/ns.pid)
				local runChrootArgs=""
				if [ "$privileged" = "1" ]; then
					echo "Entering the already started jail \`$jailName'" >&2
				else
					echo "Entering the already started jail \`$jailName' unprivileged" >&2
					runChrootArgs="-r"
				fi
				[ "$nsPid" != "" ] || echo "Unable to get the running namespace, bailing out" && execRemNS $nsPid sh -c "$(runChroot $runChrootArgs $ownPath $(prepareCmd "$runEnvironment" "$shellCommand") $@)"
				exit $?
			else # we start a new jail
				echo "This jail is not started, please start it with the \"daemon\" command" >&2
				exit 0
			fi
		;;

		*)
			echo "$0 : start|stop|shell|daemon"
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

		cmdParse $s1 $ownPath $@
	;;
esac
