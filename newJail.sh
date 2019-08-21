#! /bin/sh

filesystem="
/bin
/boot
/dev
/dev/pts
/etc
/etc/pam.d
/lib
/lib/tls
/lib/security
/home
/mnt
/opt
/proc
/sbin
/sys
/root
/tmp
/run
/usr
/usr/bin
/usr/sbin
/usr/lib
/usr/lib/tls
/usr/libexec
/usr/local
/usr/local/bin
/usr/local/lib
/usr/local/lib/tls
/usr/local/sbin
/var
/var/account
/var/cache
/var/empty
/var/games
/var/lock
/var/log
/var/mail
/var/opt
/var/pid
/var/run
/var/spool
/var/state
/var/tmp
/var/yp
"

case "$(readlink -f /proc/$$/exe)" in
	*dash)
		echo "We don't support dash"
		exit 1
	;;

	*)
		sh="$(readlink -f /proc/$$/exe)"
		echo "using shell : $sh"
	;;
esac

if [ "$1" = "" ]; then
	echo "please input the name of the new directory to instantiate"
	exit 1
fi

if [ "$2" = "" ]; then
	echo "please also input a service name (for the creation of a username and group)"
	exit 1
fi

if [ -e $1 ]; then
	echo "invalid path given, file or directory already exists"
	exit 1
fi

uid=$(id -u)
gid=$(id -g)

ownPath=$(dirname $0)

# convert the path of this script to an absolute path
if [ "$ownPath" = "." ]; then
	ownPath=$PWD
else
	if [ "${ownPath:0:1}" = "/" ]; then
		# absolute path, we do nothing
		break;
	else
		# relative path
		ownPath=$PWD/$ownPath
	fi
fi

if [ ! -e $ownPath/busybox/busybox ]; then
	echo "Please run make in $ownPath to compile the necessary dependencies"
	exit 1
fi

jailName=$(basename $1)
newChrootHolder=$1
newChrootDir=$newChrootHolder/root
echo "Instantiating directory : " $newChrootDir

mkdir $newChrootHolder
mkdir $newChrootHolder/run
mkdir $newChrootDir

touch $newChrootHolder/startRoot.sh # this is to make cpDep detect the new style jail

for path in $filesystem ; do
	mkdir $newChrootDir/$path
	chmod 704 $newChrootDir/$path
	#chown 0 ${1}/$path
	#chgrp 0 ${1}/$path
done

if [ -h /lib64 ]; then
	echo "Linking /lib to /lib64"
	ln -s /lib $newChrootDir/lib64
else
	mkdir $newChrootDir/lib64
fi

function genPass() {
	len=$1
	cat /dev/urandom | head -c $(($len * 2)) | base64 | tr '/' '@' | head -c $len
}


echo "Populating the /etc configuration files"
# localtime
$sh $ownPath/cpDep.sh $newChrootHolder /etc/ /etc/localtime
# group
cat >> $newChrootDir/etc/group << EOF
root:x:0:
$2:x:$gid:
EOF
chmod 644 $newChrootDir/etc/group
# passwd
cat >> $newChrootDir/etc/passwd << EOF
root:x:0:0::/root:/bin/false
nobody:x:99:99::/dev/null:/bin/false
$2:x:$uid:$gid::/home:/bin/false
EOF
# shadow
cat >> $newChrootDir/etc/shadow << EOF
root:$($ownPath/cryptPass $(genPass 200) $(genPass 50)):0:0:99999:7:::
nobody:!:0:0:99999:7:::
$2:!:0:0:99999:7:::
EOF
chmod 600 $newChrootDir/etc/shadow

# shells
cat >> $newChrootDir/etc/shells << EOF
$sh
/bin/false
EOF

cat > $newChrootHolder/startRoot.sh << EOF
#! $sh
# Don't change anything in this script! Use rootCustomConfig.sh for your changes!

_JAILTOOLS_RUNNING=1

if [ \$UID != 0 ]; then
	echo "This script has to be run with root permissions as it calls the command chroot"
	exit 1
fi

ownPath=\$(dirname \$0)

. \$ownPath/rootCustomConfig.sh

user=$2

# dev mount points : read-write, no-exec
read -d '' devMountPoints << EOF
@EOF

# read-only mount points with exec
read -d '' roMountPoints << EOF
/usr/share/locale
/usr/lib/locale
/usr/lib/gconv
@EOF

# read-write mount points with exec
read -d '' rwMountPoints << EOF
@EOF

# mkdir -p with a mode only applies the mode to the last child dir... this function applies the mode to all directories
function cmkdir() {
	local args=\$@

	local mode=\$(echo \$args | sed -e 's/ /\n/g' | sed -ne '/^-m$/ {N; s/-m\n//g; p;q}' -e '/--mode/ {s/--mode=//; p; q}')
	local modeLess=\$(echo \$args | sed -e 's/ /\n/g' | sed -e '/^-m$/ {N; s/.*//g; d}' -e '/--mode/ {s/.*//; d}')

	local callArgs=""
	if [ "\$mode" != "" ]; then
		local callArgs="\$callArgs --mode=\$mode"
	fi

	for dir in \$modeLess; do
		local subdirs=\$(echo \$dir | sed -e 's/\//\n/g')
		local parentdir=""
		for subdir in \$subdirs; do
			if [ ! -d \$parentdir\$subdir ]; then
				mkdir \$callArgs \$parentdir\$subdir
			fi
			if [ "\$parentdir" = "" ]; then
				parentdir="\$subdir/"
			else
				parentdir="\$parentdir\$subdir/"
			fi
		done
	done
}

function mountMany() {
	local rootDir=\$1
	local mountOps=\$2
	shift 2

	for mount in \$@; do
		if [ ! -d \$rootDir/\$mount ]; then
			echo \$rootDir/\$mount does not exist, creating it
			cmkdir -m 755 \$rootDir/\$mount
		fi
		mountpoint \$rootDir/\$mount > /dev/null || mount \$mountOps --bind \$mount \$rootDir/\$mount
	done
}

# isDefaultRoute - Route all packets through this bridge, you can only do that on a single bridge (valid values : "true" or "false")
# vethInternal - The inter jail veth device name.
# vethExternal - The bridge's veth device name connected to the remote bridge.
# externalNetnsId - The remote bridge's netns id name.
# externalBridgeName - The remote bridge's device name.
# internalIpNum - a number from 1 to 254 assigned to the vethInternal device. In the same class C network as the bridge.
# leave externalNetnsId empty if it's to connect to a bridge on the namespace 0 (base system)
function joinBridge() {
	local isDefaultRoute=\$1
	local vethInternal=\$2
	local vethExternal=\$3
	local externalNetnsId=\$4
	local externalBridgeName=\$5
	local internalIpNum=\$6
	local ipIntBitmask=24 # hardcoded for now, we set this very rarely
	# this function makes use of the netnsId global variable

	ip link add \$vethExternal type veth peer name \$vethInternal
	ip link set \$vethExternal up
	ip link set \$vethInternal netns \$netnsId
	ip netns exec \$netnsId ip link set \$vethInternal up

	if [ "\$externalNetnsId" = "" ]; then
		local masterBridgeIp=\$(ip addr show \$externalBridgeName | grep 'inet ' | grep "scope link" | sed -e 's/^.*inet \([^/]*\)\/.*$/\1/')
	else
		local masterBridgeIp=\$(ip netns exec \$externalNetnsId ip addr show \$externalBridgeName | grep 'inet ' | grep "scope link" | sed -e 's/^.*inet \([^/]*\)\/.*$/\1/')
	fi
	local masterBridgeIpCore=\$(echo \$masterBridgeIp | sed -e 's/\(.*\)\.[0-9]*$/\1/')
	local newIntIp=\${masterBridgeIpCore}.\$internalIpNum

	if [ "\$externalNetnsId" = "" ]; then
		ip netns exec \$netnsId ip addr add \$newIntIp/\$ipIntBitmask dev \$vethInternal scope link
	else
		ip link set \$vethExternal netns \$externalNetnsId
		ip netns exec \$externalNetnsId ip link set \$vethExternal up
		ip netns exec \$netnsId ip addr add \$newIntIp/\$ipIntBitmask dev \$vethInternal scope link
	fi

	if [ "\$isDefaultRoute" = "true" ]; then
		ip netns exec \$netnsId ip route add default via \$masterBridgeIp dev \$vethInternal proto kernel src \$newIntIp
	fi

	if [ "\$externalNetnsId" = "" ]; then
		brctl addif \$externalBridgeName \$vethExternal
	else
		ip netns exec \$externalNetnsId brctl addif \$externalBridgeName \$vethExternal
	fi
}

function leaveBridge() {
	local vethExternal=\$1
	local externalNetnsId=\$2
	local externalBridgeName=\$3

	if [ "\$externalNetnsId" = "" ]; then
		brctl delif \$externalBridgeName \$vethExternal
	else
		ip netns exec \$externalNetnsId brctl delif \$externalBridgeName \$vethExternal
	fi

}

# jailLocation - The jail that hosts a bridge you wish to connect to.
# isDefaultRoute - Route all packets through this bridge, you can only do that on a single bridge (valid values : "true" or "false")
# internalIpNum - internalIpNum - a number from 1 to 254 assigned to the vethInternal device. In the same class C network as the bridge.
# this loads data from a jail automatically and connects to their bridge
function joinBridgeByJail() {
	local jailLocation=\$1
	local isDefaultRoute=\$2
	local internalIpNum=\$3

	if [ -d \$jailLocation/root ] && [ -d \$jailLocation/run ] && [ -f \$jailLocation/startRoot.sh ] && [ -f \$jailLocation/rootCustomConfig.sh ]; then
		local confPath=\$jailLocation/rootCustomConfig.sh

		local neededConfig=\$(cat \$confPath | sed -ne '/^jailName=/ p; /^createBridge=/ p; /^bridgeName=/ p; /^bridgeIp=/ p; /^bridgeIpBitmask=/ p; /^netnsId=/ p;')

		local remJailName=\$(echo \$neededConfig | sed -e 's/^.*jailName=\([^ ]*\).*$/\1/')
		local remIsCreateBridge=\$(echo \$neededConfig | sed -e 's/^.*createBridge=\([^ ]*\).*$/\1/')
		local remBridgeName=\$(echo \$neededConfig | sed -e 's/^.*bridgeName=\([^ ]*\).*$/\1/')
		local remBridgeIp=\$(echo \$neededConfig | sed -e 's/^.*bridgeIp=\([^ ]*\).*$/\1/')
		local remBridgeIpBitmask=\$(echo \$neededConfig | sed -e 's/^.*bridgeIpBitmask=\([^ ]*\).*$/\1/')
		local remNetnsId=\$(echo \$neededConfig | sed -e 's/^.*netnsId=\([^ ]*\).*$/\1/')

		if [ "\$remIsCreateBridge" != "true" ]; then
			echo "This jail does not have a bridge, bailing out."
			return
		fi

		if [ "\$remBridgeName" = '\${jailName:0:13}' ]; then
			local remBridgeName=\${remJailName:0:13}
		fi
		if [ "\$remNetnsId" = '\${jailName:0:13}' ]; then
			local remNetnsId=\${remJailName:0:13}
		fi

		joinBridge "\$isDefaultRoute" "\$remJailName" "\$jailName" "\$remNetnsId" "\$remBridgeName" "\$internalIpNum"
	else
		echo "Supplied jail path is not a valid supported jail."
	fi
}

# jailLocation - The jail that hosts a bridge you wish to disconnect from.
function leaveBridgeByJail() {
	local jailLocation=\$1

	if [ -d \$jailLocation/root ] && [ -d \$jailLocation/run ] && [ -f \$jailLocation/startRoot.sh ] && [ -f \$jailLocation/rootCustomConfig.sh ]; then
		local confPath=\$jailLocation/rootCustomConfig.sh

		local neededConfig=\$(cat \$confPath | sed -ne '/^jailName=/ p; /^createBridge=/ p; /^bridgeName=/ p; /^bridgeIp=/ p; /^bridgeIpBitmask=/ p; /^netnsId=/ p;')

		local remJailName=\$(echo \$neededConfig | sed -e 's/^.*jailName=\([^ ]*\).*$/\1/')
		local remIsCreateBridge=\$(echo \$neededConfig | sed -e 's/^.*createBridge=\([^ ]*\).*$/\1/')
		local remBridgeName=\$(echo \$neededConfig | sed -e 's/^.*bridgeName=\([^ ]*\).*$/\1/')
		local remNetnsId=\$(echo \$neededConfig | sed -e 's/^.*netnsId=\([^ ]*\).*$/\1/')

		if [ "\$remIsCreateBridge" != "true" ]; then
			echo "This jail does not have a bridge, bailing out."
			return
		fi

		if [ "\$remBridgeName" = '\${jailName:0:13}' ]; then
			local remBridgeName=\${remJailName:0:13}
		fi
		if [ "\$remNetnsId" = '\${jailName:0:13}' ]; then
			local remNetnsId=\${remJailName:0:13}
		fi

		leaveBridge "\$jailName" "\$remNetnsId" "\$remBridgeName"
	fi
}

function prepareChroot() {
	local rootDir=\$1
	mount --bind \$rootDir/root \$rootDir/root

	if [ "\$(stat -c %u \$rootDir/root/etc/shadow)" != "0" ]; then
		chown root:root \$rootDir/root/etc/shadow
	fi
	if [ "\$(stat -c %u \$rootDir/root/etc/group)" != "0" ]; then
		chown root:root \$rootDir/root/etc/group
	fi
	if [ "\$(stat -c %u \$rootDir/root/etc/passwd)" != "0" ]; then
		chown root:root \$rootDir/root/etc/passwd
	fi

	# dev
	mountMany \$rootDir/root "-o rw,noexec" \$devMountPoints
	mountMany \$rootDir/root "-o ro,exec" \$roMountPoints
	mountMany \$rootDir/root "-o defaults" \$rwMountPoints

	mountMany \$rootDir/root "-o rw,noexec" \$devMountPoints_CUSTOM
	mountMany \$rootDir/root "-o ro,exec" \$roMountPoints_CUSTOM
	mountMany \$rootDir/root "-o defaults" \$rwMountPoints_CUSTOM

	if [ "\$jailNet" = "true" ]; then
		# setting up the network interface
		ip netns add \$netnsId

		# loopback device is activated
		ip netns exec \$netnsId ip link set up lo

		if [ "\$createBridge" = "true" ]; then
			# setting up the bridge
			ip netns exec \$netnsId brctl addbr \$bridgeName
			ip netns exec \$netnsId ip addr add \$bridgeIp/\$bridgeIpBitmask dev \$bridgeName scope link
			ip netns exec \$netnsId ip link set up \$bridgeName
		fi

		if [ "\$configNet" = "true" ]; then
			ip link add \$vethExt type veth peer name \$vethInt
			ip link set \$vethExt up
			ip link set \$vethInt netns \$netnsId
			ip netns exec \$netnsId ip link set \$vethInt up

			ip netns exec \$netnsId ip addr add \$ipInt/\$ipIntBitmask dev \$vethInt scope link

			ip addr add \$extIp/\$extIpBitmask dev \$vethExt scope link
			ip link set \$vethExt up
			ip netns exec \$netnsId ip route add default via \$extIp dev \$vethInt proto kernel src \$ipInt

			shortJailName=\${jailName:0:13}
			case "\$firewallType" in
				"shorewall")
					for pth in zones interfaces policy snat rules; do
						if [ ! -d \$firewallPath/\${pth}.d ]; then
							mkdir \$firewallPath/\${pth}.d
						fi
					done

					echo "\$firewallZoneName ipv4" > \$firewallPath/zones.d/\$shortJailName.zones
					echo "\$firewallZoneName \$vethExt" > \$firewallPath/interfaces.d/\$shortJailName.interfaces
					echo "\$firewallZoneName \$firewallNetZone ACCEPT" > \$firewallPath/policy.d/\$shortJailName.policy
					if [ "\$snatEth" != "" ]; then
						echo "MASQUERADE \$vethExt \$snatEth" > \$firewallPath/snat.d/\$shortJailName.snat
					fi
					echo "" > \$firewallPath/rules.d/\$shortJailName.rules
				;;

				"iptables")
					baseAddr=\$(echo \$ipInt | sed -e 's/\.[0-9]*$/\.0/') # convert 192.168.xxx.xxx to 192.168.xxx.0

					iptables -t nat -N \${snatEth}_\${shortJailName}_masq
					iptables -t nat -A POSTROUTING -o \$snatEth -j \${snatEth}_\${shortJailName}_masq
					iptables -t nat -A \${snatEth}_\${shortJailName}_masq -s \$baseAddr/\$ipIntBitmask -j MASQUERADE

					iptables -t filter -I FORWARD -i \$vethExt -o \$snatEth -j ACCEPT
					iptables -t filter -I FORWARD -i \$snatEth -o \$vethExt -m state --state ESTABLISHED,RELATED -j ACCEPT
				;;

				*)
				;;
			esac
		fi
	fi

	prepCustom \$rootDir

	[ "\$firewallType" = "shorewall" ] && [ "\$configNet" = "true" ] && shorewall restart > /dev/null 2> /dev/null
}

function startChroot() {
	local rootDir=\$1

	prepareChroot \$rootDir

	startCustom \$rootDir \$user
	# if you need to add logs, just pipe them to the directory : run/someLog.log
}

function runChroot() {
	local rootDir=\$1
	shift 1
	local cmds=\$@

	if [ "\$cmds" = "" ]; then
		local args=""
	else
		local args="-c \"\$cmds\""
	fi

	if [ "\$jailNet" = "true" ]; then
		env - PATH=/usr/bin:/bin USER=\$user HOME=/home UID=$uid HOSTNAME=nowhere.here \\
			ip netns exec \$netnsId \\
			unshare -mpfiuC $sh -c "mount -tproc none \$rootDir/root/proc; chroot --userspec=$uid:$gid \$rootDir/root /bin/sh \$args"
	else
		env - PATH=/usr/bin:/bin USER=\$user HOME=/home UID=$uid HOSTNAME=nowhere.here \\
			unshare -mpfiuC $sh -c "mount -tproc none \$rootDir/root/proc; chroot --userspec=$uid:$gid \$rootDir/root /bin/sh \$args"
	fi

}

function runShell() {
	local rootDir=\$1
	prepareChroot \$rootDir

	runChroot \$rootDir
}

function stopChroot() {
	local rootDir=\$1

	stopCustom \$rootDir

	if [ "\$jailNet" = "true" ]; then
		if [ "\$createBridge" = "true" ]; then
			ip netns exec \$netnsId ip link set down \$bridgeName
			ip netns exec \$netnsId brctl delbr \$bridgeName
		fi

		ip netns delete \$netnsId

		if [ "\$configNet" = "true" ]; then
			shortJailName=\${jailName:0:13}
			case "\$firewallType" in
				"shorewall")
					for fwSection in zones interfaces policy snat rules; do
						[ -e \$firewallPath/\$fwSection.d/\$shortJailName.\$fwSection ] && rm \$firewallPath/\$fwSection.d/\$shortJailName.\$fwSection
					done
					shorewall restart > /dev/null 2> /dev/null
									;;

				"iptables")
					iptables -t nat -D POSTROUTING -o \$snatEth -j \${snatEth}_\${shortJailName}_masq
					iptables -t nat -D \${snatEth}_\${shortJailName}_masq -s \$baseAddr/\$ipIntBitmask -j MASQUERADE

					iptables -t filter -D FORWARD -i \$vethExt -o \$snatEth -j ACCEPT
					iptables -t filter -D FORWARD -i \$snatEth -o \$vethExt -m state --state ESTABLISHED,RELATED -j ACCEPT
					iptables -t nat -X \${snatEth}_\${shortJailName}_masq
				;;

				*)
				;;
			esac
		fi
	fi

	for mount in \$devMountPoints \$roMountPoints \$rwMountPoints \$devMountPoints_CUSTOM \$roMountPoints_CUSTOM \$rwMountPoints_CUSTOM; do
		mountpoint \$rootDir/root/\$mount > /dev/null && umount \$rootDir/root/\$mount
	done
	mountpoint \$rootDir/root > /dev/null && umount \$rootDir/root
}

case \$1 in

	*)
		cmdParse \$1 \$ownPath
	;;
esac

EOF

cat > $newChrootHolder/rootCustomConfig.sh << EOF
#! $sh

# this is the file in which you can put your custom jail's configuration in shell script form

if [ "\$_JAILTOOLS_RUNNING" = "" ]; then
	echo "Don\'t run this script directly, run startRoot.sh instead"
	exit 1
fi

################# Configuration ###############

jailName=$jailName

# the namespace name for this jail
netnsId=\${jailName:0:13}

# if you set to false, the chroot will have exactly the same
# network access as the base system.
jailNet=true

# If set to true, we will create a new bridge with the name
# bridgeName(see below) in our ns creatensId. This permits
# external sources to join it and potentially gaining access
# to services on this jail.
createBridge=true
# this is the bridge we will either create if createBridge=true
# or join if it is false
bridgeName=\${jailName:0:13}
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

# this is the external IP we use only if configNet=true
extIp=192.168.12.1
extIpBitmask=24

# firewall select
# we support : shorewall, iptables
# Any other value will disable basic automatic firewall
# masquerade (forwarding) configuration.
# Note that both the iptables and shorewall implementations
# only allow outbound connections (and their response). It
# does not allow any inbound connections by themselves. For
# that you have to push in your own rules.
# Ideally, you should push these rules from the
# rootCustomConfig script because rules are deleted after the
# jail is closed, by default.
# only used if configNet=true
firewallType=shorewall

# shorewall specific options Section, only used if
# configNet=true
firewallPath=/etc/shorewall
firewallNetZone=net
firewallZoneName=\${jailName:0:5}

# all firewalls options section
# the network interface by which we will masquerade our
# connection (only used if configNet=true)
snatEth=eth0

# chroot internal IP
# the one liner script is to make sure it is of the same network
# class as the extIp.
# Just change the ending number to set the IP.
# defaults to "2"
ipInt=\$(echo \$extIp | sed -e 's/^\(.*\)\.[0-9]*$/\1\./')2
# chroot internal IP mask
ipIntBitmask=24
# the external veth interface name (only 15 characters maximum)
vethExt=\${jailName:0:13}ex
# the internal veth interface name (only 15 characters maximum)
vethInt=\${jailName:0:13}in

################# Mount Points ################

# it's important to note that these mount points will *only* mount a directory
# exactly at the same location as the base system but inside the jail.
# so if you put /etc/ssl in the read-only mount points, the place it will be mounted
# is /etc/ssl in the jail. If you want more flexibility, you will have to mount
# manually like the Xauthority example in the function prepCustom.

# dev mount points : read-write, no-exec
read -d '' devMountPoints_CUSTOM << EOF
@EOF

# read-only mount points with exec
read -d '' roMountPoints_CUSTOM << EOF
@EOF

# read-write mount points with exec
read -d '' rwMountPoints_CUSTOM << EOF
@EOF

################ Functions ###################

# this is called before the shell command and of course the start command
# put your firewall rules here
function prepCustom() {
	local rootDir=\$1

	# Note : We use the path /home/yourUser as a place holder for your home directory.
	# It is necessary to use a full path rather than the \$HOME env. variable because
	# don't forget that this is being run as root.

	# mounting Xauthority manually (crucial for supporting X11)
	# mount --bind /home/yourUser/.Xauthority \$rootDir/root/home/.Xauthority

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

	# firewall shorewall examples :
	# Note : There is no need to remove these from stopCustom as they are automatically removed.
	# Note : won't work unless configNet=true and firewallType=shorewall

	# incoming

	# We allow the base system to connect to our jail (all ports) :
	# echo "fw \$firewallZoneName ACCEPT" >> \$firewallPath/policy.d/\$jailName.policy

	# We allow the base system to connect to our jail specifically only to the port 8000 :
	# echo "ACCEPT	fw	\$firewallZoneName tcp 8000" >> \$firewallPath/rules.d/\$jailName.rules

	# We allow the net to connect to our jail specifically to the port 8000 from the port 80 (by dnat) :
	# internet -> port 80 -> firewall's dnat -> jail's port 8000
	# echo "DNAT \$firewallNetZone \$firewallZoneName:\$extIp:8000 tcp 80" >> \$firewallPath/rules.d/\$jailName.rules

	# outgoing

	# We allow the jail all access to the net zone (all ports) :
	# echo "\$firewallZoneName \$firewallNetZone ACCEPT" >> \$firewallPath/policy.d/\$jailName.policy

	# We allow the jail all access to the base system (all ports) :
	# echo "\$firewallZoneName fw ACCEPT" >> \$firewallPath/policy.d/\$jailName.policy

	# We allow the jail only access to the base system's port 25 :
	# echo "ACCEPT \$firewallZoneName fw tcp 25" >> \$firewallPath/rules.d/\$jailName.rules

}

function startCustom() {
	local rootDir=\$1

	# if you want both the "shell" command and this "start" command to have the same parameters,
	# place your instructions in prepCustom and only place "start" specific instructions here.

	# put your chroot starting scripts/instructions here
	# here's an example, by default this is the same as the shell command.
	# just supply your commands to it's arguments.
	runChroot \$rootDir

	# if you need to add logs, just pipe them to the directory : \$rootDir/run/someLog.log
}

function stopCustom() {
	local rootDir=\$1
	# put your stop instructions here

	# this is to be used in combination with the mount --bind example in prepCustom
	# mountpoint \$rootDir/root/home/.Xauthority > /dev/null && umount \$rootDir/root/home/.Xauthority

	# this is to be used in combination with the joinBridgeByJail line in prepCustom
	# leaveBridgeByJail /home/yourUser/jails/tor

	# this is to be used in combination with the joinBridge line in prepCustom
	# leaveBridge "extInt" "" "br0"
}

function cmdParse() {
	local args=\$1
	local ownPath=\$2

	case \$args in

		start)
			startChroot \$ownPath
			stopChroot \$ownPath
		;;

		stop)
			stopChroot \$ownPath
		;;

		shell)
			runShell \$ownPath
			stopChroot \$ownPath
		;;

		restart)
			stopChroot \$ownPath
			startChroot \$ownPath
		;;

		*)
			echo "\$0 : start|stop|restart|shell"
		;;
	esac
}

EOF

# we fix the EOF inside the script
sed -e "s/^\@EOF$/EOF/g" -i $newChrootHolder/startRoot.sh

sed -e "s/^\@EOF$/EOF/g" -i $newChrootHolder/rootCustomConfig.sh

echo "Copying pam security libraries"
#sh cpDep.sh $newChrootHolder /lib/security /lib/security/*

echo "Copying /etc data"
$sh $ownPath/cpDep.sh $newChrootHolder /etc/ /etc/{termcap,services,protocols,nsswitch.conf,ld.so.cache,inputrc,hostname,resolv.conf,host.conf,hosts}
if [ -e /etc/terminfo ]; then
	$sh $ownPath/cpDep.sh $newChrootHolder /etc/ /etc/terminfo
fi

sh $ownPath/cpDep.sh $newChrootHolder /bin $ownPath/busybox/busybox

for app in $($ownPath/busybox/busybox --list-full); do
	ln -s /bin/busybox ${newChrootDir}/$app
done





# we append these to update.sh
echo "# end basic dependencies" >> $newChrootHolder/update.sh
echo "" >> $newChrootHolder/update.sh

echo "All done"
exit 0

