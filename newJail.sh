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

ownPath=$(dirname $0)

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

echo "Adding /bin/false to the jail"
$sh $ownPath/cpDep.sh $newChrootHolder /bin/ /bin/false

echo "Populating the /etc configuration files"
# localtime
$sh $ownPath/cpDep.sh $newChrootHolder /etc/ /etc/localtime
# group
cat >> $newChrootDir/etc/group << EOF
root:x:0:
$2:x:$GID:
EOF
# passwd
cat >> $newChrootDir/etc/passwd << EOF
root:x:0:0::/root:/bin/false
$2:x:$UID:$GID::/home:/bin/false
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
		if [ "\$createBridge" = "true" ]; then
			# setting up the bridge
			brctl addbr \$bridgeName
			ip addr add \$bridgeIp/\$bridgeIpBitmask dev \$bridgeName scope link
			ip link set up \$bridgeName
		fi

		# setting up the network interface
		if [ "\$creatensId" = "true" ]; then
			ip netns add \$netnsId
		fi
		ip link add \$vethExt type veth peer name \$vethInt
		ip link set \$vethExt up
		ip link set \$vethInt netns \$netnsId
		ip netns exec \$netnsId ip link set \$vethInt up
		ip netns exec \$netnsId ip addr add \$ipInt/\$ipIntBitmask dev \$vethInt scope link
		ip netns exec \$netnsId ip route add default via \$bridgeIp dev \$vethInt proto kernel src \$ipInt

		brctl addif \$bridgeName \$vethExt

		if [ "\$createBridge" = "true" ]; then

			case "\$firewallType" in
				"shorewall")
					for pth in zones interfaces policy snat ; do
						if [ ! -d \$firewallPath/\${pth}.d ]; then
							mkdir \$firewallPath/\${pth}.d
						fi
					done

					echo "\$firewallZoneName ipv4" > \$firewallPath/zones.d/\$bridgeName.zones
					echo "\$firewallZoneName \$bridgeName" > \$firewallPath/interfaces.d/\$bridgeName.interfaces
					echo "\$firewallZoneName \$firewallNetZone ACCEPT" > \$firewallPath/policy.d/\$bridgeName.policy
					if [ "\$snatEth" != "" ]; then
						echo "MASQUERADE \$bridgeName \$snatEth" > \$firewallPath/snat.d/\$bridgeName.snat
					fi
					echo "" > \$firewallPath/rules.d/\$bridgeName.rules
				;;

				"iptables")
					baseAddr=\$(echo \$ipInt | sed -e 's/\.[0-9]*$/\.0/') # convert 192.168.xxx.xxx to 192.168.xxx.0

					iptables -t nat -N \${snatEth}_\${bridgeName}_masq
					iptables -t nat -A POSTROUTING -o \$snatEth -j \${snatEth}_test_masq
					iptables -t nat -A \${snatEth}_\${bridgeName}_masq -s \$baseAddr/\$ipIntBitmask -j MASQUERADE

					iptables -t filter -I FORWARD -i \$bridgeName -o \$snatEth -j ACCEPT
					iptables -t filter -I FORWARD -i \$snatEth -o \$bridgeName -m state --state ESTABLISHED,RELATED -j ACCEPT
				;;

				*)
				;;
			esac
		fi
	fi

	prepCustom \$rootDir

	[ "\$firewallType" = "shorewall" ] && shorewall restart > /dev/null 2> /dev/null
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
		env - PATH=/usr/bin:/bin USER=\$user HOME=/home UID=$UID HOSTNAME=nowhere.here \\
			ip netns exec \$netnsId \\
			unshare -mpf $sh -c "mount -tproc none \$rootDir/root/proc; chroot --userspec=$UID:$GID \$rootDir/root $sh \$args"
	else
		env - PATH=/usr/bin:/bin USER=\$user HOME=/home UID=$UID HOSTNAME=nowhere.here \\
			unshare -mpf $sh -c "mount -tproc none \$rootDir/root/proc; chroot --userspec=$UID:$GID \$rootDir/root $sh \$args"
	fi

}

function runShell() {
	local rootDir=\$1
	prepareChroot \$rootDir

	runChroot \$rootDir
}

function stopChroot() {
	local rootDir=\$1

	if [ "\$jailNet" = "true" ]; then
		if [ "\$createBridge" = "true" ]; then
			ip netns delete \$bridgeName
			ip link set down \$bridgeName
			brctl delbr \$bridgeName

			case "\$firewallType" in
				"shorewall")
					for fwSection in zones interfaces policy snat rules; do
						[ -e \$firewallPath/\$fwSection.d/\$bridgeName.\$fwSection ] && rm \$firewallPath/\$fwSection.d/\$bridgeName.\$fwSection
					done
					shorewall restart > /dev/null 2> /dev/null
				;;

				"iptables")
					iptables -t nat -D POSTROUTING -o \$snatEth -j \${snatEth}_test_masq
					iptables -t nat -D \${snatEth}_\${bridgeName}_masq -s \$baseAddr/\$ipIntBitmask -j MASQUERADE

					iptables -t filter -D FORWARD -i \$bridgeName -o \$snatEth -j ACCEPT
					iptables -t filter -D FORWARD -i \$snatEth -o \$bridgeName -m state --state ESTABLISHED,RELATED -j ACCEPT
					iptables -t nat -X \${snatEth}_\${bridgeName}_masq
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

	stopCustom \$rootDir
}

cmdParse \$1 \$ownPath

EOF

cat > $newChrootHolder/rootCustomConfig.sh << EOF
#! $sh

# this is the file in which you can put your custom jail's configuration in shell script form

if [ "\$_JAILTOOLS_RUNNING" = "" ]; then
	echo "Don\'t run this script directly, run startRoot.sh instead"
	exit 1
fi

################# Configuration ###############

# if you set to false, the chroot will have exactly the same
# network access as the base system.
jailNet=true
# If set to true, we will create a new bridge with the name
# bridgeName(see below), otherwise we will join an existing
# bridge with the name set in the variable bridgeName(below)
createBridge=true
# only used if createBridge=true
bridgeIp=192.168.12.1
bridgeIpBitmask=24

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
firewallType=shorewall

# shorewall specific options Section
firewallPath=/etc/shorewall
firewallNetZone=net
firewallZoneName=jl1

# all firewalls options section
# the network interface by which we will masquerade our
# connection
snatEth=enp1s0

# create the namespace ID. If you intend this to be combined
# with an already existing namespace, put false here and write
# the namespace name to join to netnsId
creatensId=true
netnsId=$newChrootHolder

# this is the bridge we will either create if createBridge=true
# or join if it is false
bridgeName=$newChrootHolder
# chroot internal IP
ipInt=192.168.12.2
# chroot internal IP mask
ipIntBitmask=24
# the external veth interface name
vethExt=veth0
# the internal veth interface name
vethInt=veth1

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
	local rootDir=$1
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

#echo "Copying minimal locale and gconv data"
mkdir $newChrootDir/usr/lib/locale
#sh cpDep.sh $newChrootHolder /usr/lib/locale/en_US /usr/lib/locale/en_US
mkdir $newChrootDir/usr/lib/gconv
#sh cpDep.sh $newChrootHolder /usr/lib/gconv /usr/lib/gconv

echo "Copying terminfo data"
cp -RL /usr/share/{terminfo,misc} $newChrootDir/usr/share
$sh $ownPath/cpDep.sh $newChrootHolder /etc/ /etc/{termcap,services,protocols,nsswitch.conf,ld.so.cache,inputrc,hostname,resolv.conf,host.conf,hosts}
if [ -e /etc/terminfo ]; then
	$sh $ownPath/cpDep.sh $newChrootHolder /etc/ /etc/terminfo
fi

echo "Copying the nss libraries"
$sh $ownPath/cpDep.sh $newChrootHolder /usr/lib/ /lib/libnss*

# if you want the standard binaries for using sh scripts
$sh $ownPath/cpDep.sh $newChrootHolder /bin/ /bin/{sh,ls,mkdir,cat,chgrp,chmod,chown,cp,grep,ln,kill,rm,rmdir,sed,sh,sleep,touch,basename,dirname,uname,mktemp,cmp,md5sum,realpath,mv,id,readlink,env,tr,[,fold,which,date,stat}
$sh $ownPath/cpDep.sh $newChrootHolder $(dirname $sh) $sh

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

