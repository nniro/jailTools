#! @SHELL@

# this is the file in which you can put your custom jail's configuration in shell script form

case "$(readlink -f /proc/$$/exe)" in
	*zsh)
		setopt shwordsplit
	;;
esac

if [ "$_JAILTOOLS_RUNNING" = "" ]; then
	echo "Don\'t run this script directly, run startRoot.sh instead" >&2
	exit 1
fi

# substring offset <optional length> string
# cuts a string at the starting offset and wanted length.
substring() {
        local init=$1; shift
        if [ "$2" != "" ]; then toFetch="\(.\{$1\}\).*"; shift; else local toFetch="\(.*\)"; fi
        echo "$1" | $bb sed -e "s/^.\{$init\}$toFetch$/\1/"
}

################# Configuration ###############

jailName=@JAILNAME@

# if you set to false, the chroot will have exactly the same
# network access as the base system.
jailNet=true

# If set to true, we will create a new bridge with the name
# bridgeName(see below) in our ns creatensId. This permits
# external sources to join it and potentially gaining access
# to services on this jail.
createBridge=false
# this is the bridge we will create if createBridge=true
bridgeName=$(substring 0 13 $jailName)
# only used if createBridge=true
bridgeIp=192.168.99.1
bridgeIpBitmask=24

# If you put true here the script will create a veth pair on the base
# namespace and in the jail and do it's best to allow the internet through
# these. The default routing will pass through this device to potentially
# give internet access through it, depending on your choice of firewall below.
# When it's false, you can still manually connect to the net if you like or
# join a bridge to gain fine grained access to ressources.
# Only valid if jailNet=true
configNet=false

# this is the external IP.
# Only valid if configNet=true
extIp=192.168.12.1
extIpBitmask=24

# This is automatically set but you can change this value
# if you like. You may for example decide to make a jail
# only pass through a tunnel or a vpn. Otherwise, keep
# this value to the default value.
netInterface=@DEFAULTNETINTERFACE@

# This boolean sets if you want your jail to
# gain full internet access using a technique called
# SNAT or Masquerading. This will make the jail able to
# access the internet and your LAN as if it was on the
# host system.
# Only valid if configNet=true
setNetAccess=false

# chroot internal IP
# the one liner script is to make sure it is of the same network
# class as the extIp.
# Just change the ending number to set the IP.
# defaults to "2"
ipInt=$(echo $extIp | $bb sed -e 's/^\(.*\)\.[0-9]*$/\1\./')2
# chroot internal IP mask
ipIntBitmask=24
# These are setup only if configNet is true
# the external veth interface name (only 15 characters maximum)
vethExt=$(substring 0 13 $jailName)ex
# the internal veth interface name (only 15 characters maximum)
vethInt=$(substring 0 13 $jailName)in


################# Mount Points ################

# it's important to note that these mount points will *only* mount a directory
# exactly at the same location as the base system but inside the jail.
# so if you put /etc/ssl in the read-only mount points, the place it will be mounted
# is /etc/ssl in the jail. If you want more flexibility, you will have to mount
# manually like the Xauthority example in the function prepCustom.

# dev mount points : read-write, no-exec
devMountPoints_CUSTOM=$(cat << EOF
EOF
)

# read-only mount points with exec
roMountPoints_CUSTOM=$(cat << EOF
/usr/share/locale
/usr/lib/locale
/usr/lib/gconv
EOF
)

# read-write mount points with exec
rwMountPoints_CUSTOM=$(cat << EOF
EOF
)


################ Functions ###################

# this is called before the shell command and of course the start command
# put your firewall rules here
prepCustom() {
	local rootDir=$1

	# Note : We use the path /home/yourUser as a place holder for your home directory.
	# It is necessary to use a full path rather than the $HOME env. variable because
	# don't forget that this is being run as root.

	# To add devices (in the /dev folder) of the jail use the addDevices function. You
	# don't need to add the starting /dev path.
	# If for example you wanted to add the 'null' 'urandom' and 'zero' devices you would do :
	# addDevices $rootDir null urandom zero
	#
	# Note that the jail's /dev directory is now a tmpfs so it's content is purged every time
	# the jail is stopped. Also note that addDevices puts exactly the same file permissions
	# as those on the base system.

	# we check if the file first exists. If not, we create it.
	# you can do the same thing with directories by doing "[ ! -d ..." and "&& mkdir ..."
	# [ ! -e $rootDir/root/home/.Xauthority ] && touch .Xauthority
	#
	# mounting Xauthority manually (crucial for supporting X11)
	# execNS mount --bind /home/yourUser/.Xauthority $rootDir/root/home/.Xauthority

	# joinBridgeByJail <jail path> <set as default route> <our last IP bit>
	# To join an already running jail called tor at the path, we don't set it
	# as our default internet route and we assign the interface the last IP bit of 3
	# so for example if tor's bridge's IP is 192.168.11.1 we are automatically assigned
	# the IP : 192.168.11.3
	# joinBridgeByJail /home/yourUser/jails/tor "false" "3"

	# To join a bridge not from a jail.
	# The 1st argument is for if we want to route our internet through that bridge.
	# the 2nd and 3rd arguments : intInt and extInt are the interface names for the
	# internal interface and the external interface respecfully.
	# We left the 4th argument empty because this bridge is on the base system. If it
	# was in it's own namespace, we would use the namespace name there.
	# The 5th argument is the bridge's device name
	# The 6th argument is the last IP bit. For example if tor's bridge's IP is 192.168.11.1
	# we are automatically assigned the IP : 192.168.11.3
	# joinBridge "false" "intInt" "extInt" "" "br0" "3"

	# firewall
	# synopsis :
	# externalFirewall $rootDir [command] <command arguments...>
	# 	commands :
	#		dnat - [udp or tcp] [input interface] [output interface] [source port] [destination address] [destination port]
	#			This makes it possible to forward an external port to one of the port on the jail itself.
	#
	#		dnatTcp - [input interface] [output interface] [source port] [destination address] [destination port]
	#			Tcp variant of dnat
	#			see 'dnat'
	#		dnatUdp - [input interface] [output interface] [source port] [destination address] [destination port]
	#			Udp variant of dnat
	#			see 'dnat'
	#		openPort - [interface from] [interface to] [tcp or udp] [destination port]
	#			opens a port (and also allow communications through it) from an origin to a destination network interface
	#				on a specific port or a port range using this format 'min:max'.
	#
	#		openTcpPort - [interface from] [interface to] [destination port]
	#			Tcp variant of openPort
	#			see 'openPort'
	#		openUdpPort - [interface from] [interface to] [destination port]
	#			Udp variant of openPort
	#			see 'openPort'
	#		allowConnection - [tcp or udp] [output interface] [destination address] [destination port]
	#			In the case that the command blockAll was used, use this command to fine grain
	#			what is allowed also supports a port range using this format 'min:max'.
	#
	#		allowTcpConnection - [output interface] [destination address] [destination port]
	#			Tcp variant of allowConnection
	#			see 'allowConnection'
	#		allowUdpConnection - [output interface] [destination address] [destination port]
	#			Udp variant of allowConnection
	#			see 'allowConnection'
	#		blockAll
	#			block all incoming and outgoing connections to a jail
	#		snat - [the interface connected to the outbound network] [the interface from which the packets originate]
	#			This permits internet access to the jail. It is also called Masquerading.
	#
	#
	# examples :
	#

	# incoming

	# We allow the base system to connect to our jail (all ports) :
	# externalFirewall $rootDir openTcpPort $vethExt $vethInt 1:65535

	# We allow the base system to connect to our jail specifically only to the tcp port 8000 :
	# externalFirewall $rootDir openTcpPort $vethExt $vethInt 8000

	# We allow the net to connect to our jail specifically to the tcp port 8000 from the port 80 (by dnat) :
	# internet -> port 80 -> firewall's dnat -> jail's port 8000
	# externalFirewall $rootDir dnatTcp eth0 $vethExt 80 $ipInt 8000

	# outgoing

	# We allow the jail access to the base system's tcp port 25 :
	# externalFirewall $rootDir openTcpPort $vethInt $vethExt 25

	# We allow the jail all access to the base system (all tcp ports) :
	# externalFirewall $rootDir openTcpPort $vethInt $vethExt 1:65535
}

startCustom() {
	local rootDir=$1

	# if you want both the "shell" command and this "start" command to have the same parameters,
	# place your instructions in prepCustom and only place "start" specific instructions here.

	# put your chroot starting scripts/instructions here
	# here's an example, by default this is the same as the shell command.
	# just supply your commands to it's arguments.
	# If you want to use your own command with environment variables, do it like so :
	# runJail $rootDir FOO=bar sh someScript.sh
	# you can't do it like so :
	# runJail $rootDir env - FOO=bar sh someScript.sh
	# this would nullify important environment variables we set in runJail/runChroot
	# You can override the defaults too, just set them using the above method.
	runJail $rootDir

	# if you need to add logs, just pipe them to the directory : $rootDir/run/someLog.log

	return $?
}

stopCustom() {
	local rootDir=$1
	# put your stop instructions here

	# this is to be used in combination with the mount --bind example in prepCustom
	# execNS mountpoint $rootDir/root/home/.Xauthority >/dev/null && umount $rootDir/root/home/.Xauthority

	# this is to be used in combination with the joinBridgeByJail line in prepCustom
	# leaveBridgeByJail /home/yourUser/jails/tor

	# this is to be used in combination with the joinBridge line in prepCustom
	# leaveBridge "extInt" "" "br0"
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
			runJail -d $ownPath
			err=$?
			stopChroot $ownPath
			exit $err
		;;

		start)
			prepareChroot $ownPath || exit 1
			startCustom $ownPath
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
				innerNSpid=$nsPid
				[ "$nsPid" != "" ] || echo "Unable to get the running namespace, bailing out" && execNS sh -c "$(runChroot $runChrootArgs $ownPath $@)"
				exit $?
			else # we start a new jail
				runJail $ownPath
				err=$?
				stopChroot $ownPath
				exit $err
			fi
		;;

		*)
			echo "$0 : start|stop|shell|daemon"
		;;
	esac
}
