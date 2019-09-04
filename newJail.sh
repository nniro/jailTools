#! /bin/sh

filesystem=$(cat << EOF
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
EOF
)

case "$(readlink -f /proc/$$/exe)" in
	*zsh)
		setopt shwordsplit
		sh="$(readlink -f /proc/$$/exe)"
		echo "using shell : $sh"
	;;

	*)
		sh="$(readlink -f /proc/$$/exe)"
		echo "using shell : $sh"
	;;
esac

if [ "$1" = "" ]; then
	echo "Synopsis : $0 <path and name> [main jail user name] [main jail user group name]"
	echo "please input the name of the new directory to instantiate and optionally a name for the main jail's user name and optionally a name for the main jail's group name"
	exit 1
fi

jailPath=$(dirname $1)
jailName=$(basename $1)

[ "$2" = "" ] && mainJailUsername=$jailName || mainJailUsername=$2
[ "$3" = "" ] && mainJailUsergroup=$jailName || mainJailUsergroup=$3

if [ -e $1 ]; then
	echo "invalid path given, file or directory already exists"
	exit 1
fi

# substring offset <optional length> string
# cuts a string at the starting offset and wanted length.
substring() {
        local init=$1; shift
        if [ "$2" != "" ]; then toFetch="\(.\{$1\}\).*"; shift; else local toFetch="\(.*\)"; fi
        echo "$1" | sed -e "s/^.\{$init\}$toFetch$/\1/"
}

uid=$(id -u)
gid=$(id -g)

ownPath=$(dirname $0)

# convert the path of this script to an absolute path
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

if [ ! -e $ownPath/busybox/busybox ]; then
	echo "Please run make in \`$ownPath' to compile the necessary dependencies"
	exit 1
fi

# check for mandatory commands
for cmd in chroot unshare mount umount mountpoint ip; do
	cmdPath="${cmd}Path"
	eval "$cmdPath"="$(command which $cmd 2>/dev/null)"
	eval "cmdPath=\${$cmdPath}"

	if [ "$cmdPath" = "" ]; then
		echo "Cannot find the command \`$cmd'. It is mandatory, bailing out."
		exit 1
	fi
done

# check the kernel's namespace support
unshareSupport=$($sh $ownPath/testUnshare.sh $unsharePath)

if $(echo $unshareSupport | sed -ne '/n/ q 0; q 1'); then # check for network namespace support
	netNS=true
	# we remove this bit from the variable because we use it differently from the other namespaces.
	unshareSupport=$(echo $unshareSupport | sed -e 's/n//')
else
	netNS=false
fi

if $(echo $unshareSupport | sed -ne '/m/ q 1; q 0'); then # check for mount namespace support
	echo "Linux kernel Mount namespace support was not detected. It mandatory to use this tool. Bailing out."
	exit 1
fi

if $(echo $unshareSupport | sed -ne '/U/ q 0; q 1'); then # check for user namespace support
	# we remove this bit from the variable because we do not yet support it.
	unshareSupport=$(echo $unshareSupport | sed -e 's/U//')
fi

# optional commands

brctlPath=$(command which brctl 2>/dev/null)

if [ "$brctlPath" = "" ]; then
	hasBrctl=false
	brctlPath=brctl
else
	hasBrctl=true
fi

iptablesPath=$(command which iptables 2>/dev/null)

if [ "$iptablesPath" = "" ]; then
	hasIptables=false
	iptablesPath=iptables
else
	hasIptables=true
fi

jailName=$(basename $1)
newChrootHolder=$1
newChrootDir=$newChrootHolder/root
echo "Instantiating directory : " $newChrootDir

mkdir $newChrootHolder
mkdir $newChrootHolder/run
mkdir $newChrootDir

touch $newChrootHolder/startRoot.sh # this is to make cpDep detect the new style jail
touch $newChrootHolder/rootCustomConfig.sh

for fPath in $filesystem; do
	mkdir $newChrootDir/$fPath
	chmod 704 $newChrootDir/$fPath
done

if [ -h /lib64 ]; then
	echo "Linking /lib to /lib64"
	ln -s /lib $newChrootDir/lib64
else
	mkdir $newChrootDir/lib64
fi

genPass() {
	len=$1
	cat /dev/urandom | head -c $(($len * 2)) | base64 | tr '/' '@' | head -c $len
}

echo "Populating the /etc configuration files"
# localtime
$sh $ownPath/cpDep.sh $newChrootHolder /etc/ /etc/localtime
# group
cat >> $newChrootDir/etc/group << EOF
root:x:0:
$mainJailUsergroup:x:$gid:
EOF
chmod 644 $newChrootDir/etc/group
# passwd
cat >> $newChrootDir/etc/passwd << EOF
root:x:0:0::/root:/bin/false
nobody:x:99:99::/dev/null:/bin/false
$mainJailUsername:x:$uid:$gid::/home:/bin/false
EOF
chmod 644 $newChrootDir/etc/passwd
# shadow
cat >> $newChrootDir/etc/shadow << EOF
root:$($ownPath/cryptPass $(genPass 200) $(genPass 50)):0:0:99999:7:::
nobody:!:0:0:99999:7:::
$mainJailUsername:!:0:0:99999:7:::
EOF
chmod 600 $newChrootDir/etc/shadow
# shells
cat >> $newChrootDir/etc/shells << EOF
/bin/sh
/bin/false
EOF

cat > $newChrootHolder/startRoot.sh << EOF
#! $sh
# Don't change anything in this script! Use rootCustomConfig.sh for your changes!

_JAILTOOLS_RUNNING=1

if [ "\$(id -u)" != "0" ]; then
	echo "This script has to be run with root permissions as it calls the command chroot"
	exit 1
fi

ownPath=\$(dirname \$0)

# convert the path of this script to an absolute path
if [ "\$ownPath" = "." ]; then
	ownPath=\$PWD
else
	if [ "\$(substring 0 1 \$ownPath)" = "/" ]; then
		# absolute path, we do nothing
		:
	else
		# relative path
		ownPath=\$PWD/\$ownPath
	fi
fi

. \$ownPath/rootCustomConfig.sh

user=$mainJailUsername

netNS=$netNS
hasBrctl=$hasBrctl
hasIptables=$hasIptables

if [ "\$netNS" = "false" ] && [ "\$jailNet" = "true" ]; then
	jailNet=false
	echo "jailNet is set to false automatically as it needs network namespace support which is not available."
fi

if [ "\$hasBrctl" = "false" ] && [ "\$createBridge" = "true" ]; then
	createBridge=false
	echo "The variable createBridge is set to true but it needs the command \\\`brctl' which is not available. Setting createBridge to false."
fi

if [ "\$configNet" = "true" ]; then
	if [ "\$firewallType" = "iptables" ] && [ "\$hasIptables" = "false" ]; then
		echo "The firewall \\\`iptables' was chosen but it needs the command \\\`iptables' which is not available or it's not in the available path. Setting configNet to false."
		configNet=false
	fi
fi

if [ "\$(cat /proc/sys/net/ipv4/ip_forward)" = "0" ]; then
	configNet=false
	echo "The ip_forward bit in /proc/sys/net/ipv4/ip_forward is disabled. This has to be enabled to get handled network support. Setting configNet to false."
	echo "\tPlease do (as root) : echo 1 > /proc/sys/net/ipv4/ip_forward  or find the method suitable for your distribution to activate IP forwarding."
fi

# dev mount points : read-write, no-exec
devMountPoints=\$(cat << EOF
@EOF
)

# read-only mount points with exec
roMountPoints=\$(cat << EOF
/usr/share/locale
/usr/lib/locale
/usr/lib/gconv
@EOF
)

# read-write mount points with exec
rwMountPoints=\$(cat << EOF
@EOF
)

# mkdir -p with a mode only applies the mode to the last child dir... this function applies the mode to all directories
cmkdir() {
        local mode="\$(echo "\$@" | sed -e 's/ /\n/g' | sed -ne '/^-m$/ {N; s/-m\n//g; p;q}' -e '/--mode/ {s/--mode=//; p; q}')"
        local modeLess="\$(echo "\$@" | sed -e 's/ /\n/g' | sed -e '/^-m$/ {N; s/.*//g; d}' -e '/--mode/ {s/.*//; d}' | sed -e 's/\/\//\//g')"

        local callArgs=""
        if [ "\$mode" != "" ]; then
                local callArgs="--mode=\$mode"
        fi

        for dir in \$(echo \$modeLess); do
                local subdirs="\$(echo \$dir | sed -e 's/\//\n/g')"
		if [ "\$(substring 0 1 \$dir)" = "/" ]; then # checking for an absolute path
			local parentdir="/"
		else # relative path
	                local parentdir=""
		fi
                for subdir in \$(echo \$subdirs); do
                        if [ ! -d \$parentdir\$subdir ]; then
                                mkdir \$callArgs \$parentdir\$subdir
                        fi
                        if [ "\$parentdir" = "" ]; then
                                local parentdir="\$subdir/"
                        else
                                local parentdir="\$parentdir\$subdir/"
                        fi
                done
        done
}

mountMany() {
	local rootDir=\$1
	local mountOps=\$2
	shift 2

	for mount in \$(echo \$@); do
		if [ ! -d "\$rootDir/\$mount" ]; then
			echo \$rootDir/\$mount does not exist, creating it
			cmkdir -m 755 \$rootDir/\$mount
		fi
		$mountpointPath \$rootDir/\$mount > /dev/null || $mountPath -o \$mountOps --bind \$mount \$rootDir/\$mount
	done
}

# isDefaultRoute - Route all packets through this bridge, you can only do that on a single bridge (valid values : "true" or "false")
# vethInternal - The inter jail veth device name.
# vethExternal - The bridge's veth device name connected to the remote bridge.
# externalNetnsId - The remote bridge's netns id name.
# externalBridgeName - The remote bridge's device name.
# internalIpNum - a number from 1 to 254 assigned to the vethInternal device. In the same class C network as the bridge.
# leave externalNetnsId empty if it's to connect to a bridge on the namespace 0 (base system)
joinBridge() {
	local isDefaultRoute=\$1
	local vethInternal=\$2
	local vethExternal=\$3
	local externalNetnsId=\$4
	local externalBridgeName=\$5
	local internalIpNum=\$6
	local ipIntBitmask=24 # hardcoded for now, we set this very rarely
	# this function makes use of the netnsId global variable

	$ipPath link add \$vethExternal type veth peer name \$vethInternal
	$ipPath link set \$vethExternal up
	$ipPath link set \$vethInternal netns \$netnsId
	$ipPath netns exec \$netnsId $ipPath link set \$vethInternal up

	if [ "\$externalNetnsId" = "" ]; then
		local masterBridgeIp=\$($ipPath addr show \$externalBridgeName | grep 'inet ' | grep "scope link" | sed -e 's/^.*inet \([^/]*\)\/.*$/\1/')
	else
		local masterBridgeIp=\$($ipPath netns exec \$externalNetnsId $ipPath addr show \$externalBridgeName | grep 'inet ' | grep "scope link" | sed -e 's/^.*inet \([^/]*\)\/.*$/\1/')
	fi
	local masterBridgeIpCore=\$(echo \$masterBridgeIp | sed -e 's/\(.*\)\.[0-9]*$/\1/')
	local newIntIp=\${masterBridgeIpCore}.\$internalIpNum

	if [ "\$externalNetnsId" = "" ]; then
		$ipPath netns exec \$netnsId $ipPath addr add \$newIntIp/\$ipIntBitmask dev \$vethInternal scope link
	else
		$ipPath link set \$vethExternal netns \$externalNetnsId
		$ipPath netns exec \$externalNetnsId $ipPath link set \$vethExternal up
		$ipPath netns exec \$netnsId $ipPath addr add \$newIntIp/\$ipIntBitmask dev \$vethInternal scope link
	fi

	if [ "\$isDefaultRoute" = "true" ]; then
		$ipPath netns exec \$netnsId $ipPath route add default via \$masterBridgeIp dev \$vethInternal proto kernel src \$newIntIp
	fi

	if [ "\$externalNetnsId" = "" ]; then
		$brctlPath addif \$externalBridgeName \$vethExternal
	else
		$ipPath netns exec \$externalNetnsId $brctlPath addif \$externalBridgeName \$vethExternal
	fi
}

leaveBridge() {
	local vethExternal=\$1
	local externalNetnsId=\$2
	local externalBridgeName=\$3

	if [ "\$externalNetnsId" = "" ]; then
		$brctlPath delif \$externalBridgeName \$vethExternal
	else
		$ipPath netns exec \$externalNetnsId $brctlPath delif \$externalBridgeName \$vethExternal
	fi
}

# jailLocation - The jail that hosts a bridge you wish to connect to.
# isDefaultRoute - Route all packets through this bridge, you can only do that on a single bridge (valid values : "true" or "false")
# internalIpNum - internalIpNum - a number from 1 to 254 assigned to the vethInternal device. In the same class C network as the bridge.
# this loads data from a jail automatically and connects to their bridge
joinBridgeByJail() {
	local jailLocation=\$1
	local isDefaultRoute=\$2
	local internalIpNum=\$3

	if [ -d \$jailLocation/root ] && [ -d \$jailLocation/run ] && [ -f \$jailLocation/startRoot.sh ] && [ -f \$jailLocation/rootCustomConfig.sh ]; then
		local confPath=\$jailLocation/rootCustomConfig.sh

		local neededConfig="\$(cat \$confPath | sed -ne '/^jailName=/ p; /^createBridge=/ p; /^bridgeName=/ p; /^netnsId=/ p;')"
                for cfg in jailName createBridge bridgeName netnsId; do
                        eval "local rem\$cfg"="\$(printf "%s" "\$neededConfig" | sed -ne "/^\$cfg/ p" | sed -e 's/#.*//' | sed -e 's/^[^=]\+=\(.*\)$/\1/' | sed -e 's/\${\([^:]\+\):/\${rem\1:/' -e 's/\$\([^{(]\+\)/\$rem\1/')"
                done

                if [ "\$remcreateBridge" != "true" ]; then
                        echo "This jail does not have a bridge, bailing out."
                        return
                fi

		if \$($ipPath netns list | sed -ne "/\$remnetnsId/ q 1; $ q 0"); then
			echo "joinBridgeByJail: This jail \\\`\$remnetnsId' is not currently started, aborting joining."
			return
		fi

                # echo "Attempting to join bridge \$rembridgeName on jail \$remjailName with net ns \$remnetnsId"
                joinBridge "\$isDefaultRoute" "\$remjailName" "\$jailName" "\$remnetnsId" "\$rembridgeName" "\$internalIpNum"
	else
		echo "Supplied jail path is not a valid supported jail."
	fi
}

# jailLocation - The jail that hosts a bridge you wish to disconnect from.
leaveBridgeByJail() {
	local jailLocation=\$1

	if [ -d \$jailLocation/root ] && [ -d \$jailLocation/run ] && [ -f \$jailLocation/startRoot.sh ] && [ -f \$jailLocation/rootCustomConfig.sh ]; then
		local confPath=\$jailLocation/rootCustomConfig.sh

		local neededConfig=\$(cat \$confPath | sed -ne '/^jailName=/ p; /^createBridge=/ p; /^bridgeName=/ p; /^netnsId=/ p;')
                for cfg in jailName createBridge bridgeName netnsId; do
                        eval "local rem\$cfg"="\$(printf "%s" "\$neededConfig" | sed -ne "/^\$cfg/ p" | sed -e 's/#.*//' | sed -e 's/^[^=]\+=\(.*\)$/\1/' | sed -e 's/\${\([^:]\+\):/\${rem\1:/' -e 's/\$\([^{(]\+\)/\$rem\1/')"
                done

                if [ "\$remcreateBridge" != "true" ]; then
                        echo "This jail does not have a bridge, bailing out."
                        return
                fi

		if \$($ipPath netns list | sed -ne "/\$remnetnsId/ q 1; $ q 0"); then
			# we don't need to do anything since the bridge no longer exists, no cleaning required, bailing out
			return
		fi

		leaveBridge "\$jailName" "\$remnetnsId" "\$rembridgeName"
	fi
}

applyFirewallRules() {
	local prepRun=\$1
	if [ "\$configNet" = "true" ]; then
		shortJailName=\$(substring 0 13 \$jailName)
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

				if [ "\$snatEth" != "" ]; then
					$iptablesPath -t nat -N \${snatEth}_\${shortJailName}_masq
					$iptablesPath -t nat -A POSTROUTING -o \$snatEth -j \${snatEth}_\${shortJailName}_masq
					$iptablesPath -t nat -A \${snatEth}_\${shortJailName}_masq -s \$baseAddr/\$ipIntBitmask -j MASQUERADE

					$iptablesPath -t filter -I FORWARD -i \$vethExt -o \$snatEth -j ACCEPT
					$iptablesPath -t filter -I FORWARD -i \$snatEth -o \$vethExt -m state --state ESTABLISHED,RELATED -j ACCEPT
				fi
			;;

			*)
			;;
		esac
	fi

	# if this was run in prepareChroot, we do not run this command.
	# If this is run manually elsewhere, it has to be run to apply the
	# 	changes to shorewall
	if [ "\$prepRun" = "" ]; then
		[ "\$firewallType" = "shorewall" ] && [ "\$configNet" = "true" ] && shorewall restart > /dev/null 2> /dev/null
	fi
}

prepareChroot() {
	local rootDir=\$1

	if ! \$($ipPath netns list | sed -ne "/^\$netnsId\($\| .*$\)/ q 1; $ q 0"); then
		echo "This jail was already started, bailing out."
		return 1
	fi
	$mountPath --bind \$rootDir/root \$rootDir/root

	for etcF in shadow group passwd; do # makes sure these files are owned by root
		[ "\$(stat -c %u \$rootDir/root/etc/\$etcF)" != "0" ] && chown root:root \$rootDir/root/etc/\$etcF
	done

	# dev
	mountMany \$rootDir/root "rw,noexec" \$devMountPoints
	mountMany \$rootDir/root "ro,exec" \$roMountPoints
	mountMany \$rootDir/root "defaults" \$rwMountPoints

	mountMany \$rootDir/root "rw,noexec" \$devMountPoints_CUSTOM
	mountMany \$rootDir/root "ro,exec" \$roMountPoints_CUSTOM
	mountMany \$rootDir/root "defaults" \$rwMountPoints_CUSTOM

	if [ "\$jailNet" = "true" ]; then
		# setting up the network interface
		$ipPath netns add \$netnsId

		# loopback device is activated
		$ipPath netns exec \$netnsId $ipPath link set up lo

		if [ "\$createBridge" = "true" ]; then
			# setting up the bridge
			$ipPath netns exec \$netnsId $brctlPath addbr \$bridgeName
			$ipPath netns exec \$netnsId $ipPath addr add \$bridgeIp/\$bridgeIpBitmask dev \$bridgeName scope link
			$ipPath netns exec \$netnsId $ipPath link set up \$bridgeName
		fi

		if [ "\$configNet" = "true" ]; then
			$ipPath link add \$vethExt type veth peer name \$vethInt
			$ipPath link set \$vethExt up
			$ipPath link set \$vethInt netns \$netnsId
			$ipPath netns exec \$netnsId $ipPath link set \$vethInt up

			$ipPath netns exec \$netnsId $ipPath addr add \$ipInt/\$ipIntBitmask dev \$vethInt scope link

			$ipPath addr add \$extIp/\$extIpBitmask dev \$vethExt scope link
			$ipPath link set \$vethExt up
			$ipPath netns exec \$netnsId $ipPath route add default via \$extIp dev \$vethInt proto kernel src \$ipInt

			applyFirewallRules 1
		fi
	fi

	prepCustom \$rootDir

	[ "\$firewallType" = "shorewall" ] && [ "\$configNet" = "true" ] && shorewall restart > /dev/null 2> /dev/null
	return 0
}

runChroot() {
	local rootDir=\$1
	shift

	if [ "\$1" = "-root" ]; then
		shift
		chrootArgs=""
	else
		chrootArgs="--userspec=$uid:$gid"
	fi
	local cmds=\$@

	if [ "\$cmds" = "" ]; then
		local chrootCmd="/bin/sh"
	else
		local chrootCmd=""
                while [ "\$1" != "" ]; do
                        local chrootCmd="\$chrootCmd '\$1'"
                        shift
                done
	fi

	local preUnshare="env - PATH=/usr/bin:/bin USER=\$user HOME=/home UID=$uid HOSTNAME=nowhere.here"

	if [ "\$jailNet" = "true" ]; then
		local preUnshare="$preUnshare $ipPath netns exec \$netnsId"
	fi

	\$preUnshare $unsharePath -${unshareSupport}f $sh -c "$mountPath -tproc none \$rootDir/root/proc; $chrootPath \$chrootArgs \$rootDir/root \$chrootCmd"
}

stopChroot() {
	local rootDir=\$1

	stopCustom \$rootDir

	if [ "\$jailNet" = "true" ]; then
		if \$($ipPath netns list | sed -ne "/\$netnsId/ q 1; $ q 0"); then
			echo "netnsId \\\`\$netnsId' does not exist, exiting..."
			exit 0
		fi
		if [ "\$createBridge" = "true" ]; then
			$ipPath netns exec \$netnsId $ipPath link set down \$bridgeName
			$ipPath netns exec \$netnsId $brctlPath delbr \$bridgeName
		fi

		if [ "\$configNet" = "true" ]; then
			shortJailName=\$(substring 0 13 \$jailName)
			case "\$firewallType" in
				"shorewall")
					for fwSection in zones interfaces policy snat rules; do
						[ -e \$firewallPath/\$fwSection.d/\$shortJailName.\$fwSection ] && rm \$firewallPath/\$fwSection.d/\$shortJailName.\$fwSection
					done
					shorewall restart > /dev/null 2> /dev/null
				;;

				"iptables")
					if [ "\$snatEth" != "" ]; then
						$iptablesPath -t nat -D POSTROUTING -o \$snatEth -j \${snatEth}_\${shortJailName}_masq
						$iptablesPath -t nat -D \${snatEth}_\${shortJailName}_masq -s \$baseAddr/\$ipIntBitmask -j MASQUERADE

						$iptablesPath -t filter -D FORWARD -i \$vethExt -o \$snatEth -j ACCEPT
						$iptablesPath -t filter -D FORWARD -i \$snatEth -o \$vethExt -m state --state ESTABLISHED,RELATED -j ACCEPT
						$iptablesPath -t nat -X \${snatEth}_\${shortJailName}_masq
					fi
				;;

				*)
				;;
			esac
		fi
		$ipPath netns delete \$netnsId
	fi

	for mount in \$(echo \$devMountPoints \$roMountPoints \$rwMountPoints \$devMountPoints_CUSTOM \$roMountPoints_CUSTOM \$rwMountPoints_CUSTOM); do
		$mountpointPath \$rootDir/root/\$mount > /dev/null && $umountPath \$rootDir/root/\$mount
	done
	$mountpointPath \$rootDir/root > /dev/null 2>/dev/null && $umountPath \$rootDir/root
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

# substring offset <optional length> string
# cuts a string at the starting offset and wanted length.
substring() {
        local init=\$1; shift
        if [ "\$2" != "" ]; then toFetch="\(.\{\$1\}\).*"; shift; else local toFetch="\(.*\)"; fi
        echo "\$1" | sed -e "s/^.\{\$init\}\$toFetch$/\1/"
}

################# Configuration ###############

jailName=$jailName

# the namespace name for this jail
netnsId=\$(substring 0 13 \$jailName)

# if you set to false, the chroot will have exactly the same
# network access as the base system.
jailNet=true

# If set to true, we will create a new bridge with the name
# bridgeName(see below) in our ns creatensId. This permits
# external sources to join it and potentially gaining access
# to services on this jail.
createBridge=false
# this is the bridge we will create if createBridge=true
bridgeName=\$(substring 0 13 \$jailName)
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
firewallZoneName=\$(substring 0 5 \$jailName)

# all firewalls options section
# the network interface by which we will masquerade our
# connection (only used if configNet=true)
# leave it empty if you don't want to masquerade your connection
# through any interface.
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
vethExt=\$(substring 0 13 \$jailName)ex
# the internal veth interface name (only 15 characters maximum)
vethInt=\$(substring 0 13 \$jailName)in

################# Mount Points ################

# it's important to note that these mount points will *only* mount a directory
# exactly at the same location as the base system but inside the jail.
# so if you put /etc/ssl in the read-only mount points, the place it will be mounted
# is /etc/ssl in the jail. If you want more flexibility, you will have to mount
# manually like the Xauthority example in the function prepCustom.

# dev mount points : read-write, no-exec
devMountPoints_CUSTOM=\$(cat << EOF
@EOF
)

# read-only mount points with exec
roMountPoints_CUSTOM=\$(cat << EOF
@EOF
)

# read-write mount points with exec
rwMountPoints_CUSTOM=\$(cat << EOF
@EOF
)

################ Functions ###################

# this is called before the shell command and of course the start command
# put your firewall rules here
prepCustom() {
	local rootDir=\$1

	# Note : We use the path /home/yourUser as a place holder for your home directory.
	# It is necessary to use a full path rather than the \$HOME env. variable because
	# don't forget that this is being run as root.

	# mounting Xauthority manually (crucial for supporting X11)
	# mount --bind /home/yourUser/.Xauthority \$rootDir/root/home/.Xauthority

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

startCustom() {
	local rootDir=\$1

	# if you want both the "shell" command and this "start" command to have the same parameters,
	# place your instructions in prepCustom and only place "start" specific instructions here.

	# put your chroot starting scripts/instructions here
	# here's an example, by default this is the same as the shell command.
	# just supply your commands to it's arguments.
	runChroot \$rootDir

	# if you need to add logs, just pipe them to the directory : \$rootDir/run/someLog.log
}

stopCustom() {
	local rootDir=\$1
	# put your stop instructions here

	# this is to be used in combination with the mount --bind example in prepCustom
	# mountpoint \$rootDir/root/home/.Xauthority > /dev/null && umount \$rootDir/root/home/.Xauthority

	# this is to be used in combination with the joinBridgeByJail line in prepCustom
	# leaveBridgeByJail /home/yourUser/jails/tor

	# this is to be used in combination with the joinBridge line in prepCustom
	# leaveBridge "extInt" "" "br0"
}

cmdParse() {
	local args=\$1
	local ownPath=\$2

	case \$args in

		start)
			prepareChroot \$ownPath || exit 1
			startCustom \$ownPath
			stopChroot \$ownPath
		;;

		stop)
			stopChroot \$ownPath
		;;

		shell)
			prepareChroot \$ownPath || exit 1
			runChroot \$ownPath
			stopChroot \$ownPath
		;;

		restart)
			stopChroot \$ownPath
			prepareChroot \$ownPath || exit 1
			startCustom \$ownPath
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

echo "Copying /etc data"
etcFiles=""
for ef in termcap services protocols nsswitch.conf ld.so.cache inputrc hostname resolv.conf host.conf hosts; do etcFiles="$etcFiles /etc/$ef"; done
$sh $ownPath/cpDep.sh $newChrootHolder /etc/ $etcFiles

[ -e /etc/terminfo ] && $sh $ownPath/cpDep.sh $newChrootHolder /etc/ /etc/terminfo

$sh $ownPath/cpDep.sh $newChrootHolder /bin $ownPath/busybox/busybox

for app in $($ownPath/busybox/busybox --list-full); do ln -s /bin/busybox ${newChrootDir}/$app; done


# we append these to update.sh
echo "# end basic dependencies" >> $newChrootHolder/update.sh
echo "" >> $newChrootHolder/update.sh

echo "All done"
exit 0
