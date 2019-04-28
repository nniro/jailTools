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


echo "Populating the /etc configuration files"
# localtime
$sh $ownPath/cpDep.sh $newChrootHolder /etc/ /etc/localtime
# group
cat >> $newChrootDir/etc/group << EOF
root:x:0:
$2:x:$gid:
EOF
# passwd
cat >> $newChrootDir/etc/passwd << EOF
root:x:0:0::/root:/bin/false
$2:x:$uid:$gid::/home:/bin/false
EOF
# shadow
cat >> $newChrootDir/etc/shadow << EOF
root:$($ownPath/cryptPass $($sh $ownPath/gene.sh -f 200) $($sh $ownPath/gene.sh -f 50)):0:0:99999:7:::
$2:!:0:0:99999:7:::
EOF

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

function prepareChroot() {
	local rootDir=\$1
	mount --bind \$rootDir/root \$rootDir/root

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


		if [ "\$createBridge" = "true" ]; then
			# setting up the bridge
			ip netns exec \$netnsId brctl addbr \$bridgeName
			ip netns exec \$netnsId ip addr add \$bridgeIp/\$bridgeIpBitmask dev \$bridgeName scope link
			ip netns exec \$netnsId ip link set up \$bridgeName
		fi

		ip link add \$vethExt type veth peer name \$vethInt
		ip link set \$vethExt up
		ip link set \$vethInt netns \$netnsId
		ip netns exec \$netnsId ip link set \$vethInt up

		if [ "\$joinBridge" = "true" ]; then
			masterBridgeIp=\$(ip netns exec \$extNetnsId ip addr show \$extBridgeName | grep 'inet ' | grep "scope link" | sed -e 's/^.*inet \([^/]*\)\/.*$/\1/')
			masterBridgeIpCore=\$(echo \$masterBridgeIp | sed -e 's/\(.*\)\.[0-9]*$/\1/')
			intIpNum=\$(echo \$ipInt | sed -e 's/.*\.\([0-9]*\)$/\1/')
			newIntIp=\${masterBridgeIpCore}.\$intIpNum

			if [ "\$extNetnsId" = "" ]; then
				ip addr add \$newIntIp/\$ipIntBitmask dev \$vethInt scope link
			else
				ip link set \$vethExt netns \$extNetnsId
				ip netns exec \$extNetnsId ip link set \$vethExt up
				ip netns exec \$netnsId ip addr add \$newIntIp/\$ipIntBitmask dev \$vethInt scope link
			fi
		else
			ip netns exec \$netnsId ip addr add \$ipInt/\$ipIntBitmask dev \$vethInt scope link
		fi

		if [ "\$joinBridge" = "false" ]; then
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
		else # joinBridge = true
			ip netns exec \$netnsId ip route add default via \$masterBridgeIp dev \$vethInt proto kernel src \$newIntIp

			if [ "\$extNetnsId" = "" ]; then
				brctl addif \$extBridgeName \$vethExt
			else
				ip netns exec \$extNetnsId brctl addif \$extBridgeName \$vethExt
			fi
		fi
	fi


	prepCustom \$rootDir

	[ "\$firewallType" = "shorewall" ] && [ "\$joinBridge" = "false" ] && shorewall restart > /dev/null 2> /dev/null
}

function startChroot() {
	local rootDir=\$1

	prepareChroot \$rootDir

	startCustom \$rootDir \$user
	# if you need to add logs, just pipe them to the directory : root/run/someLog.log
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

			#ip link set down \$bridgeName
			#brctl delbr \$bridgeName
		fi

		ip netns delete \$netnsId

		if [ "\$joinBridge" = "false" ]; then
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
		else # joinBridge = true
			ip netns exec \$extNetnsId brctl delif \$extBridgeName \$vethExt
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

# for the external connection, we can either connect to an existing
# bridge with the netnsId of extNetnsId or just get our external
# interface masqueraded to the base system's network interface.
joinBridge=false
# only valid if joinBridge=true
# put the name of the bridge you want to join
# in which case the IP of the external bridge will automatically
# be assigned the last values of intIp
# for example you put 2 to intIp and the external bridgeName is
# 192.168.88 the script will automatically combine these 2 to create
# 192.168.88.2
extBridgeName=
# this is the netnsId of where the bridge resides. If the bridge
# is on the base system, leave empty.
extNetnsId=
# this is the external IP we use only if joinBridge=false
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
# only used if joinBridge=false
firewallType=shorewall

# shorewall specific options Section, only used if
# joinBridge=false
firewallPath=/etc/shorewall
firewallNetZone=net
firewallZoneName=\${jailName:0:5}

# all firewalls options section
# the network interface by which we will masquerade our
# connection (only used if joinBridge=false)
snatEth=enp1s0

# chroot internal IP
# the one liner script is to make sure it is of the same network
# class as the bridgeIp.
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
}

function startCustom() {
	local rootDir=\$1

	# put your chroot starting scripts/instructions here
	# here's an example, by default this is the same as the shell command.
	# just supply your commands to it's arguments.
	runChroot \$rootDir

	# if you need to add logs, just pipe them to the directory : \$rootDir/run/someLog.log
}

function stopCustom() {
	local rootDir=\$1
	# put your stop instructions here
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

echo "Now creating $newChrootDir/dev/null, $newChrootDir/dev/random and $newChrootDir/dev/urandom"
echo "This requires root, so we use sudo"

# this is the section we need root

sudo chown root $newChrootDir/etc/shadow
sudo chmod 600 $newChrootDir/etc/shadow
sudo chown root $newChrootDir/etc/group
sudo chmod 644 $newChrootDir/etc/group

# create quasi essential special nodes in /dev
sudo mknod $newChrootDir/dev/null c 1 3
sudo chmod 666 $newChrootDir/dev/null
sudo mknod $newChrootDir/dev/random c 1 8
sudo chmod 444 $newChrootDir/dev/random
sudo mknod $newChrootDir/dev/urandom c 1 9
sudo chmod 444 $newChrootDir/dev/urandom
sudo mknod $newChrootDir/dev/zero c 1 5
sudo chmod 444 $newChrootDir/dev/zero

# we append these to update.sh
echo "# end basic dependencies" >> $newChrootHolder/update.sh
echo "" >> $newChrootHolder/update.sh

echo "All done"
exit 0

