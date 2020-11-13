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

################# Configuration ###############

# This loads the default configuration
#
# see this file for a documentation on the available configuration.
#
. $ownPath/rootDefaultConfig.sh

networking=false

extIp=172.16.0.1

netInterface=@DEFAULTNETINTERFACE@

setNetAccess=false

# Command part

# Set the starting environment variables.
# The syntax is "variable=value"  separated by spaces and the whole between double quotes
# like so : "foo=bar one=1 two=2"
# leave empty for nothing
# these environment variables are set for these commands : daemon, start and shell
runEnvironment="DISPLAY=$DISPLAY XDG_RUNTIME_DIR=/run/user/$userUID"

# These commands are run inside the jail itself.
#
# You can also set command specific environment variables for each.
# Just set them before your command, like so :
# "foo=bar one=1 two=2 sh"
# Just remember if you put environment variables, at least put one
# command like 'sh' at the end, otherwise it won't work.
# The defaults is 'sh' when left empty.

# the command that is run when you do : jt daemon
# leave empty for the default
daemonCommand=""

# the command that is run when you do : jt start
# leave empty for the default
startCommand=""

# the command that is run when you do : jt shell
# leave empty for the default
shellCommand=""


################# Mount Points ################

# it's important to note that these mount points will *only* mount a directory
# exactly at the same location as the base system but inside the jail.
# so if you put /etc/ssl in the read-only mount points, the place it will be mounted
# is /etc/ssl in the jail. If you want more flexibility, you will have to mount
# manually like the Xauthority example in the function prepCustom.

# dev mount points : read-write, no-exec
devMountPoints=$(cat << EOF
/dev/dri
/dev/snd
/dev/input
/dev/shm
EOF
)

# read-only mount points with exec
roMountPoints=$(cat << EOF
/usr/local
/usr/lib
/usr/lib64
/usr/libexec
/usr/share
/lib
/lib64
/opt
EOF
)

# read-write mount points with exec
rwMountPoints=$(cat << EOF
/tmp/.X11-unix
/run/user
EOF
)


################ Functions ###################

# this is called before each command that start a jail (daemon and start)
# among other, put your firewall rules here
prepCustom() {
	local rootDir=$1

	# Note : We use the path /home/yourUser as a place holder for your home directory.
	# It is necessary to use a full path rather than the $HOME env. variable because
	# don't forget that this is being run as root.

	# we assume that the user's home directory is /home/<their username>
	# change this if it's not the case
	# we mount the ~/.Xauthority file which is required for X11 support
	mountSingle /home/$actualUser/.Xauthority /home/.Xauthority

	# we mount the ~/.asoundrc file which is required to gain alsa sound
	mountSingle /home/$actualUser/.asoundrc /home/.asoundrc

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

stopCustom() {
	local rootDir=$1
	# put your stop instructions here

	# It's unnecessary to unmount directories or files that were manually mounted in
	# prepCustom. This is being done automatically.

	# It's unnecessary to remove firewall rules here as this is being done automatically.

	# this is to be used in combination with the joinBridgeByJail line in prepCustom
	# leaveBridgeByJail /home/yourUser/jails/tor

	# this is to be used in combination with the joinBridge line in prepCustom
	# leaveBridge "extInt" "" "br0"
}
