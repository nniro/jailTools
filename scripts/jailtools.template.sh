#! /bin/sh

case "$(readlink -f /proc/$$/exe)" in
	*busybox)
		sh="$(readlink -f /proc/$$/exe) sh"
		echo "using shell : $sh" >&2
	;;

	*)
		sh="$(readlink -f /proc/$$/exe)"
		echo "using shell : $sh" >&2
	;;
esac

jailToolsPath=@SCRIPT_PATH@

uid=$(id -u)

. $jailToolsPath/scripts/utils.sh # detectJail

if [ "$jailToolsPath" = "ScriptPath" ]; then
	exit 1 # this script has to be installed to be used.
fi

if [ ! -e $jailToolsPath/busybox/busybox ]; then
	echo "Please run 'make' in \`$jailToolsPath' to compile the necessary dependencies first" >&2
	exit 1
fi

bb=$jailToolsPath/busybox/busybox

showHelp() {
	echo "Usage:"
	echo "  $(basename $0) <command> [jail path] [command options]"
	echo "	(leave the jail path empty for the current directory)"
	echo
	echo "Available commands :"
	printf "    help, h\t\t\tdisplay this help\n"
	printf "    new, create\t\t\tcreate a new jailTools directory\n"
	printf "    cp, cpDep\t\t\tcopy files or directories (with their shared object dependencies) into the jailTools\n"
	printf "    start, stop, shell\t\tthese are jailTools specific commands to be used inside a jailTools directory only.\n"
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

case $cmd in
	help|h)
		showHelp
	;;

	new|create)
		$sh $jailToolsPath/scripts/newJail.sh $@
		exit $?
	;;

	cp|cpDep)
		checkJailPath $1 && jPath="$1" && shift
		[ "$jPath" != "." ] || detectJail $jPath || showJailPathError

		$sh $jailToolsPath/scripts/cpDep.sh $jPath $@
		exit $?
	;;

	start|stop|shell)
		checkJailPath $1 && jPath="$1" && shift
		[ "$jPath" != "." ] || detectJail $jPath || showJailPathError

		$sh $jPath/startRoot.sh $cmd $@
		exit $?
	;;

	daemon)
		checkJailPath $1 && jPath="$1" && shift
		[ "$jPath" != "." ] || detectJail $jPath || showJailPathError

		($bb nohup $sh $jPath/startRoot.sh 'daemon' 2>&1 > $jPath/run/daemon.log) &
		#if [ "$?" != "0" ]; then echo "There was an error starting the daemon, it may already be running."; fi

		exit $?
	;;

	upgrade)
		checkJailPath $1 && jPath="$1" && shift
		[ "$jPath" != "." ] || detectJail $jPath || showJailPathError

		. $jailToolsPath/scripts/jailUpgrade.sh
		startUpgrade $jPath $@
	;;

	*)
		echo "Invalid command \`$cmd'" >&2
		exit 1
	;;
esac

exit 0
