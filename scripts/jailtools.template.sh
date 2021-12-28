# direct call without a path to 'jt'
exe=$0

if [ "$JT_PATH" != "" ]; then
	jtPath=$JT_PATH
else
	if [ "$exe" = "jt" ] && [ "$PATH" != "" ] ; then # try to find where 'jt' is located
		jtPath=""
		oldIFS=$IFS
		IFS=":"
		for entry in $PATH; do
			if [ -e "$entry/jt" ]; then
				jtPath="$entry/jt"
				break
			fi
		done
		IFS=$oldIFS

		if [ "$jtPath" = "" ]; then
			echo "Could not find 'jt' in PATH, bailing out"
			exit 1
		fi
	elif [ "$exe" = "jt" ] && [ "$PATH" = "" ]; then
		echo "PATH is empty so we can't find 'jt'."
		exit 1
	else
		jtPath=$exe
	fi
fi

# we only need to set the env variable hack when
# the program is called with a relative or absolute path.
# never from the PATH.
[ "$JT_PATH" = "" ] && [ "$exe" != "jt" ] && export JT_PATH=$jtPath
if [ "$1" = "busybox" ]; then # we act as busybox
	shift
	exec -a busybox $jtPath "$@"
fi

export JT_VERSION=

exe=$(exec -a busybox $jtPath readlink /proc/$$/exe)
bb="exec -a busybox $exe"

if echo "$exe" | $bb grep -q "busybox"; then # jt is a link to busybox
	bb="$exe"

	runner="$bb jt --run"
	shower="$bb jt --show"

	export JT_CALLER="$bb jt"
	export JT_RUNNER=$runner
	export JT_SHOWER=$shower
else

	runner="runFile"
	shower="showFile"
	if [ "$ownPath" = "" ]; then # this is for an installed 'jt'
		rPath=$($bb realpath $0 2>/dev/null)
		if [ "$?" != "0" ]; then
			export JT_CALLER=$exe
		else
			export JT_CALLER=$rPath
		fi
	else # this when 'jt' is called from a specific path
		export JT_CALLER=$exe
	fi
	bb="$JT_CALLER busybox"

	export JT_RUNNER="$JT_CALLER --run"
	export JT_SHOWER="$JT_CALLER --show"
fi
export BB=$bb
export JT_PATH=$exe

if echo "$0" | $bb grep -q '\/'; then
	ownPath=$($bb dirname $0)

	# convert the path of this script to an absolute path
	if [ "$ownPath" = "." ]; then
		ownPath=$PWD
	else
		if echo "$ownPath" | $bb grep -q '^\/'; then
			# absolute path, we do nothing
			:
		else
			# relative path
			ownPath=$PWD/$ownPath
		fi
	fi
else # this is an installed command
	ownPath=""
fi

showHelp() {
	echo "Usage:"
	echo "  $($bb basename $0) <command> [jail path] [command options]"
	echo "	(leave the jail path empty for the current directory)"
	echo
	echo "Available commands :"
	printf "    help, h\t\t\tdisplay this help\n"
	printf "    new, create\t\t\tcreate a new jail\n"
	printf "    cp, cpDep\t\t\tcopy files or directories (with their shared object dependencies) into the jail\n"
	printf "    ls, list\t\t\tlist currently started jails\n"
	printf "    start\t\t\tStart a jail.\n"
	printf "    stop\t\t\tStop a jail, however it was started (start or daemon)\n"
	printf "    daemon\t\t\tStart the jail as a daemon.\n"
	printf "    shell\t\t\tWhen a jail was previously started, you can get a new shell in it using this command.\n"
	printf "    status,s\t\t\tShow the status of the jail.\n"
	printf "    upgrade\t\t\tAttempt to upgrade a jail to the newest version.\n"
	printf "    firewall,f\t\t\tRe-apply the rules of the firewall if they are no longer present in the system's firewall.\n"
	printf "    version,v\t\t\tPrint the version of the jt superscript and if possible the version of the jail. Use '-j' to show only the jail's version.\n"
}

showJailPathError() {
	echo "These commands are only valid inside the root of a jail created by jailTools or with a valid jail path" >&2
	exit 1
}

cmd=$1
if [ "$cmd" = "" ]; then
	showHelp
	exit 0
fi
shift

@EMBEDDEDFILES_LOCATION@

eval "$($shower jt_utils)" # detectJail callGetopt

jPath="."

checkJailPath() {
	[ "$1" != "" ] && [ -d $1 ] && detectJail $1
}

opts=""
while [ "$1" != "" ]; do
	v="$(printf "%s" "$1" | $bb sed -e 's/ /%20/g')"
	[ "$opts" != "" ] && opts="${opts} $v" || opts="$v"
	shift
done

set -- $opts

case $cmd in
	help|h)
		showHelp
	;;

	new|create)
		$runner jt_new $@
		exit $?
	;;

	cp|cpDep)
		checkJailPath $1 && jPath="$1" && shift
		[ "$jPath" != "." ] || detectJail $jPath || showJailPathError

		$runner jt_cpDep $jPath $@
		exit $?
	;;

	ls|list)
		result=$(listJailsMain "$@")

		if [ "$result" = "" ]; then
			return 1
		else
			printf "%s\n" "$result"
			return 0
		fi
	;;

	start|stop|shell)
		checkJailPath $1 && jPath="$1" && shift
		[ "$jPath" != "." ] || detectJail $jPath || showJailPathError

		cd $jPath
		$bb sh ./startRoot.sh $cmd $@
		exit $?
	;;

	daemon)
		checkJailPath $1 && jPath="$1" && shift
		[ "$jPath" != "." ] || detectJail $jPath || showJailPathError

		cd $jPath
		($bb chpst -0 -1 $bb sh ./startRoot.sh 'daemon' $@ 2>./run/daemon.log) &
		#if [ "$?" != "0" ]; then echo "There was an error starting the daemon, it may already be running."; fi

		exit $?
	;;

	f|firewall)
		checkJailPath $1 && jPath="$1" && shift
		[ "$jPath" != "." ] || detectJail $jPath || showJailPathError
		rPath=$($bb realpath $jPath)

		$bb sh -c "cd $rPath; source ./jailLib.sh; checkFirewall $rPath" 2>/dev/null
		if [ "$?" = "0" ]; then
			echo "The firewall is working fine already"
		else
			echo "The firewall needs to be reapplied. Doing that now."
			$bb sh -c "cd $rPath; source ./jailLib.sh; resetFirewall $rPath" 2>/dev/null
		fi

		exit 0
	;;

	s|status)
		checkJailPath $1 && jPath="$1" && shift
		[ "$jPath" != "." ] || detectJail $jPath || showJailPathError
		rPath=$($bb realpath $jPath)

		result=$(callGetopt "status [OPTIONS]" \
		       -o "i" "ip" "display ip information" "showIp" "false" \
		       -o "p" "ps" "display process information" "showProcessStats" "false" \
		       -o "f" "firewall" "display the status of the firewall" "showFirewallStatus" "false" \
		       -- "$@")

		if [ "$?" = "0" ]; then
			#eval $result

			runInNS() {
				$bb sh -c "cd $rPath; source ./jailLib.sh; execRemNS $($bb cat $jPath/run/ns.pid) $bb chroot $rPath/root $1" 2>/dev/null
			}

			if [ "$(jailStatus $rPath)" = "1" ]; then # we check if the jail is running
				if getVarVal 'showProcessStats' "$result" >/dev/null; then
					$bb jt shell $rPath ps 2>/dev/null
				elif getVarVal 'showIp' "$result" >/dev/null; then
					runInNS "/sbin/ip addr show dev \$vethInt" | $bb sed -ne 's/ *inet \([0-9\.]*\).*/\1/ p'
				elif getVarVal 'showFirewallStatus' "$result" > /dev/null; then
					$bb sh -c "cd $rPath; source ./jailLib.sh; checkFirewall $rPath" 2>/dev/null
					result=$?

					if [ "$result" = "0" ]; then
						echo "The firewall rules are set up correctly"
					else
						echo "The firewall rules are not correct"
						exit 1
					fi
				else
					echo "The jail is running"
				fi
			else
				echo "The jail is not running"
				exit 1
			fi
		fi

		exit 0
	;;

	upgrade)
		checkJailPath $1 && jPath="$1" && shift
		[ "$jPath" != "." ] || detectJail $jPath || showJailPathError

		eval "$($shower jt_upgrade)"
		startUpgrade $jPath $@
	;;

	config)
		checkJailPath $1 && jPath="$1" && shift
		[ "$jPath" != "." ] || detectJail $jPath || showJailPathError
		rPath=$($bb realpath $jPath)

		$runner jt_config $rPath "$@"

		exit $?
	;;

	v|version)
		availJail=0
		checkJailPath $1 && jPath="$1" && shift
		[ "$jPath" != "." ] || detectJail $jPath && availJail=1

		if [ "$availJail" = "1" ]; then
			rPath=$($bb realpath $jPath)

			if [ "$1" != "-j" ]; then
				echo "jt version $JT_VERSION"
			fi
			$bb sh -c "cd $rPath; source ./jailLib.sh 2>/dev/null; echo \"jail jt version \$jailVersion\""
		else
			echo "jt version $JT_VERSION"
		fi
	;;

	*)
		echo "Invalid command \`$cmd'" >&2
		exit 1
	;;
esac

exit 0
