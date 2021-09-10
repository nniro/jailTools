#! /bin/sh

jailToolsPath=@SCRIPT_PATH@

if echo "$jailToolsPath" | grep -q "SCRIPT_PATH" ; then
	exit 1 # this script has to be installed to be used.
fi

exe=$(readlink /proc/$$/exe)

if [ "$(dirname $0)" = "." ] && [ "$(basename $exe)" = "busybox" ]; then
	bb=$exe
	ISINBUSYBOX=1

	eval "$($bb --show jt_utils)"

else
	bb=""
	ISINBUSYBOX=0
	. $jailToolsPath/scripts/paths.sh # sets the 'bb' variable
	. $jailToolsPath/scripts/utils.sh # detectJail
fi

if [ ! -e $bb ]; then
	echo "Please run 'make' in \`$jailToolsPath' to compile the necessary dependencies first" >&2
	exit 1
fi


showHelp() {
	echo "Usage:"
	echo "  $(basename $0) <command> [jail path] [command options]"
	echo "	(leave the jail path empty for the current directory)"
	echo
	echo "Available commands :"
	printf "    help, h\t\t\tdisplay this help\n"
	printf "    new, create\t\t\tcreate a new jail\n"
	printf "    cp, cpDep\t\t\tcopy files or directories (with their shared object dependencies) into the jail\n"
	printf "    start\t\t\tStart a jail.\n"
	printf "    stop\t\t\tStop a jail, however it was started (start or daemon)\n"
	printf "    daemon\t\t\tStart the jail as a daemon.\n"
	printf "    shell\t\t\tWhen a jail was previously started, you can get a new shell in it using this command.\n"
	printf "    status,s\t\t\tShow the status of the jail.\n"
	printf "    upgrade\t\t\tAttempt to upgrade a jail to the newest version.\n"
	printf "    firewall,f\t\t\tRe-apply the rules of the firewall if they are no longer present in the system's firewall.\n"
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

jPath="."

checkJailPath() {
	[ "$1" != "" ] && [ -d $1 ] && detectJail $1
}

opts=""
while [ "$1" != "" ]; do
	v="$(printf "%s" "$1" | sed -e 's/ /%20/g')"
	[ "$opts" != "" ] && opts="${opts} $v" || opts="$v"
	shift
done

set -- $opts

case $cmd in
	help|h)
		showHelp
	;;

	new|create)
		if [ "$ISINBUSYBOX" = "1" ]; then
			$bb jt_new $@
		else
			$bb sh $jailToolsPath/scripts/newJail.sh $@
		fi
		exit $?
	;;

	cp|cpDep)
		checkJailPath $1 && jPath="$1" && shift
		[ "$jPath" != "." ] || detectJail $jPath || showJailPathError

		if [ "$ISINBUSYBOX" = "1" ]; then
			$bb jt_cpDep $jPath $@
		else
			$bb sh $jailToolsPath/scripts/cpDep.sh $jPath $@
		fi
		exit $?
	;;

	start|stop|shell)
		checkJailPath $1 && jPath="$1" && shift
		[ "$jPath" != "." ] || detectJail $jPath || showJailPathError

		export BB=$bb
		$bb sh $jPath/startRoot.sh $cmd $@
		exit $?
	;;

	daemon)
		checkJailPath $1 && jPath="$1" && shift
		[ "$jPath" != "." ] || detectJail $jPath || showJailPathError

		export BB=$bb
		($bb nohup $bb sh $jPath/startRoot.sh 'daemon' $@ 2>&1 > $jPath/run/daemon.log) &
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
				$bb sh -c "export BB=$bb; cd $rPath; source ./jailLib.sh; execRemNS $(cat $jPath/run/ns.pid) $bb chroot $rPath/root $1" 2>/dev/null
			}

			if [ "$(jailStatus $rPath)" = "1" ]; then # we check if the jail is running
				if getVarVal 'showProcessStats' "$result" >/dev/null; then
					runInNS ps
				elif getVarVal 'showIp' "$result" >/dev/null; then
					runInNS "/sbin/ip addr show dev \$vethInt" | sed -ne 's/ *inet \([0-9\.]*\).*/\1/ p'
				elif getVarVal 'showFirewallStatus' "$result" > /dev/null; then
					$bb sh -c "cd $rPath; source ./jailLib.sh; checkFirewall $rPath" 2>/dev/null
					result=$?

					if [ "$result" = "0" ]; then
						echo "The firewall rules are set up correctly"
					else
						echo "The firewall rules are not correct"
					fi
				else
					echo "The jail is running"
				fi
			else
				echo "The jail is not running"
			fi
		fi

		exit 0
	;;

	upgrade)
		checkJailPath $1 && jPath="$1" && shift
		[ "$jPath" != "." ] || detectJail $jPath || showJailPathError

		if [ "$ISINBUSYBOX" = "1" ]; then
			export BB=$bb
			eval "$($bb --show jt_upgrade)"
		else
			. $jailToolsPath/scripts/jailUpgrade.sh
		fi
		startUpgrade $jPath $@
	;;

	config)
		checkJailPath $1 && jPath="$1" && shift
		[ "$jPath" != "." ] || detectJail $jPath || showJailPathError
		rPath=$($bb realpath $jPath)

		if [ "$ISINBUSYBOX" = "1" ]; then
			$bb jt_config $jailToolsPath $rPath $@
		else
			$bb sh $jailToolsPath/scripts/config.sh $jailToolsPath $rPath $@
		fi

		exit $?
	;;

	*)
		echo "Invalid command \`$cmd'" >&2
		exit 1
	;;
esac

exit 0
