#! @SHELL@
# Don't change anything in this script! Use rootCustomConfig.sh for your changes!

bb="$BB"
shower="$JT_SHOWER"
runner="$JT_RUNNER"

nsBB="/bin/busybox"

jailVersion="@JAIL_VERSION@"

if [ "$bb" = "" ] || [ "$shower" = "" ] || [ "$runner" = "" ]; then
	echo "It is no longer possible to run this script directly. The 'jt' command has to be used."
	exit 1
fi

_JAILTOOLS_RUNNING=1

privileged=0
if [ "$($bb id -u)" != "0" ]; then
	echo "You are running this script unprivileged, most features will not work" >&2
else
	privileged=1
fi

[ "$ownPath" = "" ] && ownPath=$($bb dirname $0)
firewallInstr="run/firewall.instructions"

eval "$($shower jt_utils)" # detectJail substring

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

if [ "$actualUser" = "" ]; then
	export actualUser=$($bb stat -c %U $ownPath/jailLib.sh)
fi

# we get the uid and gid of this script, this way even when ran as root, we still get the right credentials
userUID=$($bb stat -c %u $ownPath/jailLib.sh)
userGID=$($bb stat -c %g $ownPath/jailLib.sh)
userCreds="$userUID:$userGID"

. $ownPath/rootCustomConfig.sh

[ "$ipInt" = "" ] && ipInt=$(echo $extIp | $bb sed -e 's/^\(.*\)\.[0-9]*$/\1\./')2

user=@MAINJAILUSERNAME@

if [ "$privileged" = "1" ]; then
	# unprivileged user bb
	uBB="$bb chpst -u $userCreds $bb"
else
	uBB="$bb"
fi

baseEnv="$nsBB env - PATH=/usr/bin:/bin USER=$user HOME=/home HOSTNAME=nowhere.here TERM=linux"

innerNSpid=""

unshareSupport="-$(for ns in m u i n p U C; do $uBB unshare -r$ns $bb sh -c 'echo "Operation not permitted"; exit' 2>&1 | $bb grep -q "Operation not permitted" && $bb printf $ns; done)"

if [ "$unshareSupport" = "-" ]; then # FIXME, we need to support this
	echo "Detected no namespace support at all, this is not tested much so we prefer to bail out." >&2
	exit 1
fi

netNS=false
if echo $unshareSupport | $bb grep -q 'n'; then # check for network namespace support
	netNS=true
	# we remove this bit from the variable because we use it differently from the other namespaces.
	unshareSupport=$(echo $unshareSupport | $bb sed -e 's/n//')
fi

nsenterSupport=$(echo "$unshareSupport" | $bb sed -e 's/^-//' | $bb sed -e 's/\(.\)/-\1 /g')
if [ "$netNS" = "true" ]; then
	if [ "$jailNet" = "false" ] || ([ "$privileged" = "0" ] && [ "$setNetAccess" = "true" ]); then
		:
	else
		nsenterSupport="$nsenterSupport -n";
	fi
fi

if [ "$privileged" = "1" ]; then
	nsenterSupport="$(echo $nsenterSupport | $bb sed -e 's/-U//g')"
fi

# mkdir -p with a mode only applies the mode to the last child dir... this function applies the mode to all directories
# arguments :
#		-m [directory permission mode in octal]
#		-e (this makes the function output the commands rather than apply them directly)
cmkdir() {
	OPTIND=0
	local callArgs=""
	local arguments=""
	local isOutput="false" # we will output the commands rather than apply them
	local result=""
	while getopts m:e f 2>/dev/null; do
		case $f in
			m) callArgs="$callArgs --mode=$OPTARG";;
			e) isOutput="true";;
		esac
	done
	[ $(($OPTIND > 1)) = 1 ] && shift $($bb expr $OPTIND - 1)
	arguments="$@"

	for dir in $(echo $arguments); do
		local subdirs="$(echo $dir | $bb sed -e 's/\//\n/g')"
		if [ "$(substring 0 1 $dir)" = "/" ]; then # checking for an absolute path
			local parentdir="/"
		else # relative path
	                local parentdir=""
		fi
		for subdir in $(echo $subdirs); do
			if [ "$isOutput" = "false" ]; then
				if test ! -d $parentdir$subdir; then
					$bb mkdir $callArgs $parentdir$subdir
					[ "$privileged" = "1" ] && $bb chown $actualUser $parentdir$subdir
				fi
			else
				result="$result $bb mkdir -p $callArgs $parentdir$subdir;"
			fi

			if [ "$parentdir" = "" ]; then
				local parentdir="$subdir/"
			else
				local parentdir="$parentdir$subdir/"
			fi
		done
	done

	if [ "$isOutput" = "true" ]; then
		echo $result
	fi
}

addDevices() {
	local rootDir=$1
	shift
	local i=""

	while [ "$1" != "" ]; do
		i="/dev/$1"
		if [ ! -b $i ] && [ ! -c $i ]; then
			echo "invalid device \`$i'" >&2
			return 1
		else
			if [ "$($bb dirname $i)" != "/dev" ]; then
				cmkdir -e -m 755 $rootDir/root/$($bb dirname $i)
			fi

			$bb touch $rootDir/root$i
			$bb mount --bind $i $rootDir/root$i
		fi
		shift
	done

	return 0
}

mountSingle() {
	local rootDir="$1"
	local src="$2"
	local dst="$3"
	shift 3

	if [ "$rootDir" = "" ] || [ "$src" = "" ] || [ "$dst" = "" ]; then
		echo "mountSingle - The three arguments to the function : rootDir src dst  are mandatory, they all must be filled."
		exit 1
	fi

	[ ! -e $src ] && echo "mountSingle - Warning - source file or directory '$src' does not exist" >&2 && return

	echo $dst | $bb grep -q "^/" || dst="/$dst" # we expect a starting '/'

	[ ! -d $rootDir/root/$($bb dirname $dst) ] && echo "Invalid mounting path chosen" >&2 && return

	if [ -f $src ]; then
		[ ! -e $rootDir/root$dst ] && $bb touch $rootDir/root$dst
	elif [ -d $src ]; then
		[ ! -e $rootDir/root$dst ] && $bb mkdir $rootDir/root$dst
	else
		echo "Unhandled ressource type, bailing out" >&2
		return
	fi

	$bb mount --bind $src $rootDir/root$dst
}

mountMany() {
	OPTIND=0
	local rootDir=$1
	shift
	local isOutput="false"
	local result=""
	while getopts e f 2>/dev/null; do
		case $f in
			e) isOutput="true";;
		esac
	done
	[ $(($OPTIND > 1)) = 1 ] && shift $($bb expr $OPTIND - 1)
	local mountOps=$1
	shift

	for mount in $(echo $@); do
		if [ -e $mount ]; then
			if [ "$isOutput" = "false" ]; then
				if test ! -d "$rootDir/$mount"; then
					echo $rootDir/$mount does not exist, creating it >&2
					cmkdir -m 755 $rootDir/$mount
				fi
				$bb sh -c "$bb mountpoint $rootDir/$mount >/dev/null 2>/dev/null || $bb mount -o $mountOps,bind $mount $rootDir/$mount"
				# gotta remount for the options to take effect
				$bb sh -c "$bb mountpoint $rootDir/$mount >/dev/null 2>/dev/null || $bb mount -o $mountOps,remount,bind $rootDir/$mount $rootDir/$mount"
			else # isOutput = true
				result="$result if [ ! -d \"$rootDir/$mount\" ]; then $(cmkdir -e -m 755 $rootDir/$mount) fi;"
				result="$result $bb mountpoint $rootDir/$mount >/dev/null 2>/dev/null || $bb mount -o $mountOps,bind $mount $rootDir/$mount;"
				# gotta remount for the options to take effect
				result="$result $bb mountpoint $rootDir/$mount >/dev/null 2>/dev/null || $bb mount -o $mountOps,remount,bind $rootDir/$mount $rootDir/$mount;"
			fi
		else
			echo "mountMany: Warning - Path \`$mount' doesn't exist on the base system, can't mount it in the jail." >&2
		fi
	done

	if [ "$isOutput" = "true" ]; then
		echo $result
	fi
}

# isDefaultRoute - Route all packets through this bridge, you can only do that on a single bridge (valid values : "true" or "false")
# vethInternal - The inter jail veth device name.
# vethExternal - The bridge's veth device name connected to the remote bridge.
# externalNetnsId - The remote bridge's netns id name.
# externalBridgeName - The remote bridge's device name.
# internalIpNum - a number from 1 to 254 assigned to the vethInternal device. In the same class C network as the bridge.
# leave externalNetnsId empty if it's to connect to a bridge on the namespace 0 (base system)
joinBridge() {
	local isDefaultRoute=$1
	local vethInternal=$2
	local vethExternal=$3
	local externalNetnsId=$4
	local externalBridgeName=$5
	local internalIpNum=$6
	local ipIntBitmask=24 # hardcoded for now, we set this very rarely

	if [ "$privileged" = "0" ]; then
		echo "joinBridge - Error - This is not possible from an unprivileged jail" >&2
		return 1
	fi

	$bb ip link add $vethExternal type veth peer name $vethInternal || return 1
	$bb ip link set $vethExternal up || return 1
	$bb ip link set $vethInternal netns $innerNSpid || return 1
	execNS $nsBB ip link set $vethInternal up || return 1

	if [ "$externalNetnsId" = "" ]; then
		local masterBridgeIp=$($bb ip addr show $externalBridgeName | $bb grep 'inet ' | $bb grep "scope link" | $bb sed -e 's/^.*inet \([^/]*\)\/.*$/\1/')
	else
		local masterBridgeIp=$(execRemNS $externalNetnsId $nsBB ip addr show $externalBridgeName | $nsBB grep 'inet ' | $nsBB grep "scope link" | $nsBB sed -e 's/^.*inet \([^/]*\)\/.*$/\1/')
	fi
	local masterBridgeIpCore=$(echo $masterBridgeIp | $bb sed -e 's/\(.*\)\.[0-9]*$/\1/')
	local newIntIp=${masterBridgeIpCore}.$internalIpNum

	if [ "$externalNetnsId" = "" ]; then
		execNS $nsBB ip addr add $newIntIp/$ipIntBitmask dev $vethInternal scope link
	else
		$bb ip link set $vethExternal netns $externalNetnsId
		execRemNS $externalNetnsId $nsBB ip link set $vethExternal up
		execNS $nsBB ip addr add $newIntIp/$ipIntBitmask dev $vethInternal scope link
	fi

	if [ "$isDefaultRoute" = "true" ]; then
		execNS $nsBB ip route add default via $masterBridgeIp dev $vethInternal proto kernel src $newIntIp
	fi

	if [ "$externalNetnsId" = "" ]; then
		$bb brctl addif $externalBridgeName $vethExternal
	else
		execRemNS $externalNetnsId $nsBB brctl addif $externalBridgeName $vethExternal
	fi
	return 0
}

leaveBridge() {
	local vethExternal=$1
	local externalNetnsId=$2
	local externalBridgeName=$3

	if [ "$externalNetnsId" = "" ]; then
		$bb brctl delif $externalBridgeName $vethExternal
	else
		execRemNS $externalNetnsId $nsBB brctl delif $externalBridgeName $vethExternal
	fi
}

# jailLocation - The jail that hosts a bridge you wish to connect to.
# isDefaultRoute - Route all packets through this bridge, you can only do that on a single bridge (valid values : "true" or "false")
# internalIpNum - internalIpNum - a number from 1 to 254 assigned to the vethInternal device. In the same class C network as the bridge.
# this loads data from a jail automatically and connects to their bridge
joinBridgeByJail() {
	local jailLocation=$1
	local isDefaultRoute=$2
	local internalIpNum=$3

	if [ "$privileged" = "0" ]; then
		echo "joinBridgeByJail - Error - This is not possible from an unprivileged jail" >&2
		return 1
	fi

	if detectJail $jailLocation; then
		remjailName=$($runner jt_config $jailLocation -g jailName)
		remcreateBridge=$($runner jt_config $jailLocation -g createBridge)
		rembridgeName=$($runner jt_config $jailLocation -g bridgeName)

		if [ "$remcreateBridge" != "true" ]; then
			echo "joinBridgeByJail: This jail does not have a bridge, aborting joining." >&2
			return 1
		fi

		if ! jailStatus $jailLocation; then
			echo "joinBridgeByJail: This jail at \`$jailLocation' is not currently started, aborting joining." >&2
			return 1
		fi
		remnetnsId=$($bb cat $jailLocation/run/ns.pid)

		# echo "Attempting to join bridge $rembridgeName on jail $remjailName with net ns $remnetnsId" >&2
		joinBridge "$isDefaultRoute" "$remjailName" "$jailName" "$remnetnsId" "$rembridgeName" "$internalIpNum" || return 1
	else
		echo "joinBridgeByJail: Supplied jail path '$jailLocation' is not a valid supported jail." >&2
		return 1
	fi
	return 0
}

# jailLocation - The jail that hosts a bridge you wish to disconnect from.
leaveBridgeByJail() {
	local jailLocation=$1

	if detectJail $jailLocation; then
		remjailName=$($runner jt_config $jailLocation -g jailName)
		remcreateBridge=$($runner jt_config $jailLocation -g createBridge)
		rembridgeName=$($runner jt_config $jailLocation -g bridgeName)

		if [ "$remcreateBridge" != "true" ]; then
			echo "This jail does not have a bridge, bailing out." >&2
			return
		fi

		if [ ! -e "$jailLocation/run/ns.pid" ]; then
			# we don't need to do anything since the bridge no longer exists, no cleaning required, bailing out
			return
		fi
		remnetnsId=$($bb cat $jailLocation/run/ns.pid)

		leaveBridge "$jailName" "$remnetnsId" "$rembridgeName"
	fi
}

eval "$($shower jt_firewall)"

# firewall inside the jail itself
internalFirewall() { local rootDir=$1; shift; firewall $firewallInstr "internal" $@ ; }
# firewall on the base system
externalFirewall() { local rootDir=$1; shift; firewall $firewallInstr "external" $@ ; }

prepareChroot() {
	local rootDir=$1
	local unshareArgs=""
	local chrootArgs=""
	local chrootCmd="sh -c 'while :; do sleep 9999; done'"
	local preUnshare=""

	if echo $unshareSupport | $bb grep -q 'U'; then
		if [ -e /proc/sys/kernel/unprivileged_userns_clone ]; then
			if [ "$($bb cat /proc/sys/kernel/unprivileged_userns_clone)" = "0" ]; then
				if [ "$privileged" = "0" ]; then
					echo "User namespace support is currently disabled. This has to be enabled to support starting a jail unprivileged." >&2
					echo "Until the change is done, creating a jail requires privileges." >&2
					echo "\tPlease do (as root) : echo 1 > /proc/sys/kernel/unprivileged_userns_clone   or find the method suitable for your distribution to activate unprivileged user namespace clone" >&2
				fi
				userNS=false
			else
				userNS=true
			fi
		else
			userNS=true
		fi
	else
		userNS=false
	fi

	if [ "$privileged" = "0" ]; then
		if [ "$userNS" != "true" ]; then
			echo "The user namespace is not supported. Can't start an unprivileged jail without it, bailing out." >&2
			return 1
		fi
		if [ "$networking" = "true" ]; then
			networking="false"
			echo "Unprivileged jails do not support the setting networking, turning it off" >&2
		fi
	fi

	if [ "$netNS" = "false" ] && [ "$jailNet" = "true" ]; then
		jailNet=false
		echo "jailNet is set to false automatically as it needs network namespace support which is not available." >&2
	fi

	if [ "$networking" = "true" ]; then
		iptablesBin=$(PATH="$PATH:/sbin:/usr/sbin:/usr/local/sbin" command which iptables 2>/dev/null)

		if [ "$iptablesBin" = "" ]; then
			echo "The firewall \`iptables' was chosen but it needs the command \`iptables' which is not available or it's not in the available path. Setting networking to false." >&2
			networking=false
		fi
	fi

	if [ "$($bb cat /proc/sys/net/ipv4/ip_forward)" = "0" ] && [ "$privileged" = "1" ] && [ "$setNetAccess" = "true" ]; then
		networking=false
		echo "The ip_forward bit in /proc/sys/net/ipv4/ip_forward is disabled. This has to be enabled to get handled network support. Setting networking to false." >&2
		echo "\tPlease do (as root) : echo 1 > /proc/sys/net/ipv4/ip_forward  or find the method suitable for your distribution to activate IP forwarding." >&2
	fi

	# we check if $rootDir/root is owned by root, we use this technique for when the base instance was started with a privileged account
	# 	and when we use an unprivileged account to reenter the jail.
	if [ "$privileged" = "0" ] && [ "$netNS" = "true" ] && [ "$($bb stat -c %U $rootDir/root)" = "root" ]; then
		nsenterSupport="$nsenterSupport -n";
	fi

	if [ -e $rootDir/run/jail.pid ]; then
		echo "This jail was already started, bailing out." >&2
		return 1
	fi
	if [ "$privileged" = "1" ] && [ "$userNS" = "true" ] && [ "$realRootInJail" = "false" ]; then
		preUnshare="$bb chpst -u $userCreds"
		unshareArgs="-r"
	elif [ "$privileged" = "0" ] && [ "$userNS" = "true" ]; then # unprivileged
		unshareArgs="-r"
		chrootArgs=""
		unshareSupport=$(echo "$unshareSupport" | $nsBB sed -e 's/U//g')
	else
		unshareArgs=""
		chrootArgs=""
		unshareSupport=$(echo "$unshareSupport" | $nsBB sed -e 's/U//g')
	fi # unprivileged

	if [ "$jailNet" = "true" ]; then
		if [ "$privileged" = "1" ] || ([ "$privileged" = "0" ] && [ "$setNetAccess" = "false" ]); then
			unshareArgs="$unshareArgs -n"
		fi
	fi

	devMounts=$(mountMany $rootDir/root -e "rw,noexec" $devMountPoints)
	roMounts=$(mountMany $rootDir/root -e "ro,exec" $roMountPoints)
	rwMounts=$(mountMany $rootDir/root -e "defaults" $rwMountPoints)

tasksBeforePivot=$($bb cat << EOF
$bb mount -tproc none $rootDir/root/proc
$bb mount -t tmpfs -o size=256k,mode=775 tmpfs $rootDir/root/dev
$bb ln -s /proc/self/fd $rootDir/root/dev/fd
$bb sh -c ". $rootDir/jailLib.sh; addDevices $rootDir $availableDevices"
$devMounts
$roMounts
$rwMounts
$bb sh -c ". $rootDir/jailLib.sh; prepCustom $rootDir" || exit 1

if [ "$mountSys" = "true" ]; then
	if [ "$privileged" = "0" ] && [ "$setNetAccess" = "true" ]; then
		echo "Could not mount the /sys directory. As an unprivileged user, the only way this is possible is by disabling setNetAccess. Or you can always run this jail as a privileged user." >&2
	else
		$bb mount -tsysfs none $rootDir/root/sys
	fi
fi

EOF
)
	# this is the core jail instance being run in the background
	(
		$preUnshare $bb unshare $unshareArgs ${unshareSupport}f \
			-- $bb setpriv --bounding-set $corePrivileges \
			$bb sh -c "$bb mount --make-private -o bind $rootDir/root $rootDir/root; \
				$tasksBeforePivot; \
				cd $rootDir/root; \
				$bb pivot_root . $rootDir/root/root; \
				exec $nsBB chroot . sh -c \"$nsBB umount -l /root; \
					$nsBB setpriv --bounding-set $chrootPrivileges $baseEnv $chrootCmd\"" \
	) &
	innerNSpid=$!
	$bb sleep 1
	innerNSpid=$($bb pgrep -P $innerNSpid)
	$bb sleep 2

	if [ "$innerNSpid" = "" ] || ! $bb ps | $bb grep -q "^ *$innerNSpid "; then
		echo "Creating the inner namespace session failed, bailing out" >&2
		return 1
	fi

	echo $innerNSpid > $rootDir/run/ns.pid
	$bb chmod o+r $rootDir/run/ns.pid

	# dev


	if [ "$jailNet" = "true" ]; then
		# loopback device is activated
		execNS $nsBB ip link set up lo

		if [ "$createBridge" = "true" ]; then
			# NOTE that it is perfectly possible to create a bridge unprivileged
			# setting up the bridge
			execNS $nsBB brctl addbr $bridgeName
			execNS $nsBB ip addr add $bridgeIp/$bridgeIpBitmask dev $bridgeName scope link
			execNS $nsBB ip link set up $bridgeName
		fi

		if [ "$networking" = "true" ]; then
			$bb ip link add $vethExt type veth peer name $vethInt
			$bb ip link set $vethExt up
			$bb ip link set $vethInt netns $innerNSpid
			execNS $nsBB ip link set $vethInt up

			execNS $nsBB ip addr add $ipInt/$ipIntBitmask dev $vethInt scope link

			$bb ip addr add $extIp/$extIpBitmask dev $vethExt scope link
			$bb ip link set $vethExt up
			execNS $nsBB ip route add default via $extIp dev $vethInt proto kernel src $ipInt

			if [ "$setNetAccess" = "true" ] && [ "$netInterface" != "" ]; then
				if [ "$netInterface" = "auto" ]; then
					netInterface=$($bb ip route | $bb grep '^default' | $bb sed -e 's/^.* dev \([^ ]*\) .*$/\1/')
				fi

				if [ "$netInterface" = "" ]; then
					echo "Could not find a default route network interface, is the network up?" >&2
					return 1
				fi

				externalFirewall $rootDir snat $netInterface $vethExt
			fi
		fi

		# do note that networking is not necessary for this to work.
		if [ "$joinBridgeFromOtherJail" != "" ]; then
			oldIFS="$IFS"
			IFS="
			"
			for entry in $joinBridgeFromOtherJail; do
				IFS=$oldIFS
				joinBridgeByJail $entry || return 1
			done
			IFS=$oldIFS
		fi

		if [ "$joinBridge" != "" ]; then
			oldIFS="$IFS"
			IFS="
			"
			for entry in $joinBridge; do
				IFS=$oldIFS
				joinBridge $entry || return 1
			done
			IFS=$oldIFS
		fi
	fi

	if [ "$privileged" = "1" ]; then
		# this protects from an adversary to delete and recreate root owned files
		for i in bin root etc lib usr sbin sys . ; do [ -d $rootDir/root/$i ] && $bb chmod 755 $rootDir/root/$i && $bb chown root:root $rootDir/root/$i; done
		for i in passwd shadow group; do $bb chmod 600 $rootDir/root/etc/$i && $bb chown root:root $rootDir/root/etc/$i; done
		for i in passwd group; do $bb chmod 644 $rootDir/root/etc/$i; done
	fi

	return 0
}

runShell() {
	local rootDir=$1
	local nsPid=$2
	local curArgs=""
	shift 2

	while [ "$1" != "" ]; do
		arg="$(printf "%s" "$1" | $bb sed -e 's/%20/ /g')"
		if printf "%s" "$arg" | $bb grep -q ' '; then
			arg="'$arg'"
		else
			arg="$arg"
		fi
		[ "$curArgs" = "" ] && curArgs="$arg" || curArgs="$curArgs $arg"
		shift
	done

	preUnshare=""
	unshareArgs="-U --map-user=$userUID --map-group=$userGID"

	if [ "$privileged" = "1" ]; then
		if [ "$realRootInJail" = "true" ]; then
			unshareArgs=""
		else
			preUnshare="$nsBB chpst -u $userCreds"
		fi
	else
		if [ "$($bb stat -c %U $rootDir/root)" = "root" ]; then
			if [ "$netNS" = "true" ]; then
				if [ "$jailNet" = "true" ]; then
					nsenterSupport="$nsenterSupport -n";
				fi
			fi
		fi
	fi

	execRemNS $nsPid $nsBB sh -c "exec $nsBB $preUnshare unshare $unshareArgs $baseEnv $curArgs"

	return $?
}

runJail() {
	local daemonize=false
	local enableUserNS="false"
	local jailMainMounts=""
	local runAsRoot="false"
	local preUnshare=""
	OPTIND=0
	while getopts rfd f 2>/dev/null ; do
		case $f in
			r) local runAsRoot="true";; # could be real or fake root depending if this was started privileged or not.
			f) local enableUserNS="true";; # run as a fake root (with the user namespace)
			d) local daemonize="true";;
		esac
	done
	[ $(($OPTIND > 1)) = 1 ] && shift $($bb expr $OPTIND - 1)
	local rootDir=$1
	shift
	local chrootCmd=""
	if [ $(($# > 0)) = 1 ]; then
		while [ "$1" != "" ]; do
			local curArg=""
			arg="$(printf "%s" "$1" | $bb sed -e 's/%20/ /g')"
			if printf "%s" "$arg" | $bb grep -q ' '; then
				curArg="'$arg'"
			else
				curArg="$arg"
			fi
			[ "$chrootCmd" = "" ] && chrootCmd=$curArg || chrootCmd="$chrootCmd $curArg"
			shift
		done
	fi

	echo $$ > $rootDir/run/jail.pid
	$bb chmod o+r $rootDir/run/jail.pid

	if [ "$daemonize" = "true" ]; then
		if [ "$chrootCmd" = "" ]; then
			chrootCmd="sh -c 'while :; do sleep 9999; done'"
		else
			chrootCmd=$(printf "%s" "$chrootCmd" | $bb sed -e 's/\x27/"/g') # replace all ' with "
			chrootCmd="sh -c '${chrootCmd}; while :; do sleep 9999; done'"
		fi
	fi

	unshareArgs="-U --map-user=$userUID --map-group=$userGID"
	nsenterArgs="--preserve-credentials"
	if [ "$privileged" = "1" ]; then
		if [ "$runAsRoot" = "true" ]; then
			unshareArgs=""
			nsenterArgs=""
		else
			preUnshare="$nsBB chpst -u $userCreds"
		fi
	else # unprivileged
		[ "$runAsRoot" = "true" ] && unshareArgs="-r"
	fi

	execNS $preUnshare $nsBB sh -c "exec $nsBB unshare $unshareArgs $baseEnv $chrootCmd"

	return $?
}

stopChroot() {
	local rootDir=$1

	[ -e $rootDir/run/isStopping ] && exit 0

	stopCustom $rootDir

	if [ "$privileged" = "0" ]; then
		if [ "$($bb stat -c %U $rootDir/root)" = "root" ]; then
			echo "This jail was started as root and it needs to be stopped as root as well."
			exit 1
		fi
	fi

	if [ ! -e $rootDir/run/ns.pid ]; then
		echo "This jail is not running, can't stop it. Bailing out." >&2
		exit 1
	fi
	innerNSpid="$($bb cat $rootDir/run/ns.pid)"

	if [ "$innerNSpid" = "" ] || [ "$($bb pstree $innerNSpid)" = "" ]; then
		echo "This jail doesn't seem to be running anymore, please check lsns to confirm" >&2
		exit 1
	fi

	if [ "$jailNet" = "true" ]; then
		if [ "$createBridge" = "true" ]; then
			execNS $nsBB ip link set down $bridgeName
			execNS $nsBB brctl delbr $bridgeName
		fi
	fi

	local oldIFS="$IFS"
	IFS="
	"
	# removing the firewall rules inserted into the instructions file
	for cmd in $(cmdCtl "$rootDir/$firewallInstr" list); do
		IFS="$oldIFS" # we set back IFS for remCmd
		remCmd=$(printf "%s" "$cmd" | $bb sed -e 's@firewall \(.*\) \(in\|ex\)ternal \(.*\)$@firewall \1 \2ternal -d \3@')

		eval $remCmd
	done
	IFS=$oldIFS

	if [ "$privileged" = "1" ]; then
		for i in bin root etc lib usr sbin sys . ; do $bb chown $userCreds $rootDir/root/$i; done
		for i in passwd shadow group; do $bb chown $userCreds $rootDir/root/etc/$i; done
	fi

	if [ -e $rootDir/run/ns.pid ]; then
		echo "" > $rootDir/run/isStopping
		kill -9 $innerNSpid >/dev/null 2>/dev/null
		if [ "$?" = "0" ]; then
			$bb rm -f $rootDir/run/ns.pid
			$bb rm -f $rootDir/run/jail.pid
		fi
	fi
	rm $rootDir/run/isStopping
}

execNS() { execRemNS $innerNSpid "$@"; }

execRemNS() {
	local nsPid=$1
	shift
	#echo "NS [$nsPid] -- args : $nsenterSupport exec : \"$@\"" >&2
	$bb nsenter --preserve-credentials $nsenterSupport -t $nsPid -- "$@"
	return $?
}
