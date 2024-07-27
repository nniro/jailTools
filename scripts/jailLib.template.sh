#! @SHELL@
# Don't change anything in this script! Use rootCustomConfig.sh for your changes!
#
# Base library for the jail operations.
#
# direct call :
# jt --run jt_jailLib_template

bb="$BB"
shower="$JT_SHOWER"
runner="$JT_RUNNER"

nsBB="/bin/busybox"

if [ "$bb" = "" ] || [ "$shower" = "" ] || [ "$runner" = "" ]; then
	echo "It is no longer possible to run this script directly. The 'jt' command has to be used."
	exit 1
fi

if [ "$IS_RUNNING" != "1" ]; then
	_JAILTOOLS_RUNNING=1

	[ "$ownPath" = "" ] && ownPath=$($bb realpath $($bb dirname $0))
	g_firewallInstr="run/firewall.instructions"

	type isPrivileged >/dev/null 2>/dev/null
	if [ "$?" = "0" ]; then # function is available, so utils.sh was imported
		#echo "DEBUG - detected that g_utilsCmd is not necessary" >&2
		g_utilsCmd=""
	else
		g_utilsCmd="$runner jt_utils"
	fi
	type getCurVal >/dev/null 2>/dev/null
	if [ "$?" = "0" ]; then # function is available, so config.sh was imported
		#echo "DEBUG - detected that g_configCmd is not necessary" >&2
		g_configCmd=""
	else
		g_configCmd="$runner jt_config"
	fi

	if [ "$privileged" = "" ]; then
		if ! bb=$bb $g_utilsCmd isPrivileged; then
			export privileged=0
		else
			export privileged=1
		fi
	fi

	if bb=$bb $g_utilsCmd isPrivileged; then
		# unprivileged user bb
		uBB="$bb chpst -u $(bb=$bb $g_utilsCmd getBaseUserCredentials $ownPath) $bb"
	else
		uBB="$bb"
	fi

	g_baseEnv="PATH=/usr/bin:/bin USER=$(bb=$bb $g_configCmd getDefaultVal $ownPath user) HOME=/home HOSTNAME=nowhere.here TERM=linux"

	g_innerNSpid=""

	# used by isUserNamespaceSupported prepareChrootCore
	g_unshareSupport="-$(for ns in m u i n p U C; do $uBB unshare -r$ns $bb sh -c 'echo "Operation not permitted"; exit' 2>&1 | $bb grep -q "Operation not permitted" && $bb printf $ns; done)"

	if [ "$g_unshareSupport" = "-" ]; then # FIXME, we need to support this
		echo "Detected no namespace support at all, this is not tested much so we prefer to bail out." >&2
		exit 1
	fi

	# used by prepareChroot and runShell
	g_netNS=false
	if echo $g_unshareSupport | $bb grep -q 'n'; then # check for network namespace support
		g_netNS=true
		# we remove this bit from the variable because we use it differently from the other namespaces.
		g_unshareSupport=$(echo $g_unshareSupport | $bb sed -e 's/n//')
	fi

	jailNet=$(bb=$bb $g_configCmd getCurVal $ownPath jailNet)
	networking=$(bb=$bb $g_configCmd getCurVal $ownPath networking)

	# used by prepareChroot runShell execRemNS
	g_nsenterSupport=$(echo "$g_unshareSupport" | $bb sed -e 's/^-//' | $bb sed -e 's/\(.\)/-\1 /g')
	if [ "$g_netNS" = "true" ]; then
		if [ "$jailNet" = "false" ] || (! bb=$bb $g_utilsCmd isPrivileged && [ "$(bb=$bb $g_configCmd getCurVal $ownPath setNetAccess)" = "true" ]); then
			:
		else
			g_nsenterSupport="$g_nsenterSupport -n";
		fi
	fi

	if bb=$bb $g_utilsCmd isPrivileged; then
		g_nsenterSupport="$(echo $g_nsenterSupport | $bb sed -e 's/-U//g')"
	fi
fi

isStartedAsPrivileged() {
	local rootDir=$1
	[ -e $rootDir/run/.isPrivileged ]
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
				bb=$bb $g_utilsCmd cmkdir -e -m 755 $rootDir/root/$($bb dirname $i)
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

	if [ -f $src ] || [ -b $src ] || [ -c $src ]; then
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

	if [ "$isOutput" = "false" ]; then
		for mount in $(echo $@); do
			if [ -e $mount ]; then
				if [ ! -d "$rootDir/$mount" ]; then
					echo $rootDir/$mount does not exist, creating it >&2
					bb=$bb $g_utilsCmd cmkdir -m 755 $rootDir/$mount
				fi
				$bb mountpoint $rootDir/$mount >/dev/null 2>/dev/null || $bb mount -o $mountOps,bind $mount $rootDir/$mount
				# gotta remount for the options to take effect
				$bb mountpoint $rootDir/$mount >/dev/null 2>/dev/null || $bb mount -o $mountOps,remount,bind $rootDir/$mount $rootDir/$mount
			else
				echo "mountMany: Warning - Path \`$mount' doesn't exist on the base system, can't mount it in the jail." >&2
			fi
		done
	else # isOutput = true
		for mount in $(echo $@); do
			result="$result if [ ! -d \"$rootDir/$mount\" ]; then $(bb=$bb $g_utilsCmd cmkdir -e -m 755 $rootDir/$mount) fi;"
			result="$result $bb mountpoint $rootDir/$mount >/dev/null 2>/dev/null || $bb mount -o $mountOps,bind $mount $rootDir/$mount;"
			# gotta remount for the options to take effect
			result="$result $bb mountpoint $rootDir/$mount >/dev/null 2>/dev/null || $bb mount -o $mountOps,remount,bind $rootDir/$mount $rootDir/$mount;"
		done
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
	local rootDir=$1
	shift
	local isDefaultRoute=$(echo $1 | bb=$bb $g_utilsCmd stripQuotes)
	local vethInternal=$(echo $2 | bb=$bb $g_utilsCmd stripQuotes)
	local vethExternal=$(echo $3 | bb=$bb $g_utilsCmd stripQuotes)
	local externalNetnsId=$(echo $4 | bb=$bb $g_utilsCmd stripQuotes)
	local externalBridgeName=$(echo $5 | bb=$bb $g_utilsCmd stripQuotes)
	local internalIpNum=$(echo $6 | bb=$bb $g_utilsCmd stripQuotes)
	local ipIntBitmask=24 # hardcoded for now, we set this very rarely

	if ! bb=$bb $g_utilsCmd isPrivileged; then
		echo "joinBridge - Error - This is not possible from an unprivileged jail" >&2
		return 1
	fi

	$bb ip link add $vethExternal type veth peer name $vethInternal || return 1
	$bb ip link set $vethExternal up || return 1
	$bb ip link set $vethInternal netns $g_innerNSpid || return 1
	execNS $rootDir $nsBB ip link set $vethInternal up || return 1

	if [ "$externalNetnsId" = "" ]; then
		local masterBridgeIp=$($bb ip addr show $externalBridgeName | $bb grep 'inet ' | $bb grep "scope link" | $bb sed -e 's/^.*inet \([^/]*\)\/.*$/\1/')
	else
		local masterBridgeIp=$(execRemNS $rootDir $externalNetnsId $nsBB ip addr show $externalBridgeName | $nsBB grep 'inet ' | $nsBB grep "scope link" | $nsBB sed -e 's/^.*inet \([^/]*\)\/.*$/\1/')
	fi
	local masterBridgeIpCore=$(echo $masterBridgeIp | $bb sed -e 's/\(.*\)\.[0-9]*$/\1/')
	local newIntIp=${masterBridgeIpCore}.$internalIpNum

	if [ "$externalNetnsId" = "" ]; then
		execNS $rootDir $nsBB ip addr add $newIntIp/$ipIntBitmask dev $vethInternal scope link
	else
		$bb ip link set $vethExternal netns $externalNetnsId
		execRemNS $rootDir $externalNetnsId $nsBB ip link set $vethExternal up
		execNS $rootDir $nsBB ip addr add $newIntIp/$ipIntBitmask dev $vethInternal scope link
	fi

	if [ "$isDefaultRoute" = "true" ]; then
		execNS $rootDir $nsBB ip route add default via $masterBridgeIp dev $vethInternal proto kernel src $newIntIp
	fi

	if [ "$externalNetnsId" = "" ]; then
		$bb brctl addif $externalBridgeName $vethExternal
	else
		execRemNS $rootDir $externalNetnsId $nsBB brctl addif $externalBridgeName $vethExternal
	fi
	return 0
}

leaveBridge() {
	local rootDir=$1
	shift
	local vethExternal=$1
	local externalNetnsId=$2
	local externalBridgeName=$3

	if [ "$externalNetnsId" = "" ]; then
		$bb brctl delif $externalBridgeName $vethExternal
	else
		execRemNS $rootDir $externalNetnsId $nsBB brctl delif $externalBridgeName $vethExternal
	fi
}

# jailLocation - The jail that hosts a bridge you wish to connect to.
# isDefaultRoute - Route all packets through this bridge, you can only do that on a single bridge (valid values : "true" or "false")
# internalIpNum - internalIpNum - a number from 1 to 254 assigned to the vethInternal device. In the same class C network as the bridge.
# this loads data from a jail automatically and connects to their bridge
joinBridgeByJail() {
	local rootDir=$1
	shift
	local jailLocation=$(echo $1 | bb=$bb $g_utilsCmd stripQuotes)
	local isDefaultRoute=$(echo $2 | bb=$bb $g_utilsCmd stripQuotes)
	local internalIpNum=$(echo $3 | bb=$bb $g_utilsCmd stripQuotes)

	if ! bb=$bb $g_utilsCmd isPrivileged; then
		echo "joinBridgeByJail - Error - This is not possible from an unprivileged jail" >&2
		return 1
	fi

	if bb=$bb $g_utilsCmd isValidJailPath $jailLocation; then
		remjailName=$(bb=$bb $g_configCmd getCurVal $jailLocation jailName)
		remcreateBridge=$(bb=$bb $g_configCmd getCurVal $jailLocation createBridge)
		rembridgeName=$(bb=$bb $g_configCmd getCurVal $jailLocation bridgeName)

		if [ "$remcreateBridge" != "true" ]; then
			echo "joinBridgeByJail: This jail does not have a bridge, aborting joining." >&2
			return 1
		fi

		if ! bb=$bb $g_utilsCmd isJailRunning $jailLocation; then
			echo "joinBridgeByJail: This jail at \`$jailLocation' is not currently started, aborting joining." >&2
			return 1
		fi
		remnetnsId=$($bb cat $jailLocation/run/ns.pid)

		# echo "Attempting to join bridge $rembridgeName on jail $remjailName with net ns $remnetnsId" >&2
		joinBridge $rootDir "$isDefaultRoute" "$remjailName" "$(bb=$bb $g_configCmd getCurVal $rootDir jailName)" "$remnetnsId" "$rembridgeName" "$internalIpNum" || return 1
	else
		echo "joinBridgeByJail: Supplied jail path '$jailLocation' is not a valid supported jail." >&2
		return 1
	fi
	return 0
}

# jailLocation - The jail that hosts a bridge you wish to disconnect from.
leaveBridgeByJail() {
	local rootDir=$1
	local jailLocation=$2

	if bb=$bb $g_utilsCmd isValidJailPath $jailLocation; then
		remjailName=$(bb=$bb $g_configCmd getCurVal $jailLocation jailName)
		remcreateBridge=$(bb=$bb $g_configCmd getCurVal $jailLocation createBridge)
		rembridgeName=$(bb=$bb $g_configCmd getCurVal $jailLocation bridgeName)

		if [ "$remcreateBridge" != "true" ]; then
			echo "This jail does not have a bridge, bailing out." >&2
			return
		fi

		if [ ! -e "$jailLocation/run/ns.pid" ]; then
			# we don't need to do anything since the bridge no longer exists, no cleaning required, bailing out
			return
		fi
		remnetnsId=$($bb cat $jailLocation/run/ns.pid)

		leaveBridge $rootDir "$(bb=$bb $g_configCmd getCurVal $rootDir jailName)" "$remnetnsId" "$rembridgeName"
	fi
}

filterCommentedLines() { # and also empty lines
	local oldIFS=$IFS
	IFS=" "
	$bb sed -e '/^\( \|\t\)*#.*$/ d' | $bb sed -e '/^\( \|\t\)*$/ d'
	IFS=$oldIFS
}

expandSafeValues() {
	local actualUser=$1
	local userUID=$2
	local userGID=$3
	local oldIFS=$IFS
	IFS=" "
	$bb sed -e "s/\$actualUser/$actualUser/g" \
		-e "s/\$userUID/$userUID/g" \
		-e "s/\$userGID/$userGID/g"
	IFS=$oldIFS
}

expandSafeValues2() {
	$bb awk -v inputArgs="$*" '
{
	total = split(inputArgs, args, " ")

	for (i=1; i <= total; i+=2) {
		gsub(args[i], args[i + 1])
	}
	print
}
'
}

handleDirectMounts() {
	local rootDir=$1
	local actualUser=$2
	local userUID=$3
	local userGID=$4

	oldIFS="$IFS"
	local directMounts=$(bb=$bb $g_configCmd getCurVal $rootDir directMounts)
	if [ "$directMounts" != "" ]; then
		IFS="
"
		for entry in $(printf "%s" "$directMounts" | filterCommentedLines | expandSafeValues $actualUser $userUID $userGID); do
			IFS=$oldIFS
			mountSingle $rootDir $entry
		done
		IFS=$oldIFS
	fi
}

initializeCoreJail() {
	local rootDir=$1
	local actualUser=$2
	local userUID=$3
	local userGID=$4

	$bb mount -o private,bind $rootDir/root $rootDir/root
	$bb mount -tproc proc $rootDir/root/proc || $bb mount --bind /proc $rootDir/root/proc || return 1
	$bb mount -t tmpfs -o size=256k,mode=775 tmpfs $rootDir/root/dev
	$bb mkdir $rootDir/root/dev/pts
	$bb mount -t devpts -o ptmxmode=0666 none $rootDir/root/dev/pts
	$bb touch $rootDir/root/dev/ptmx
	$bb mount -o bind $rootDir/root/dev/pts/ptmx $rootDir/root/dev/ptmx
	$bb ln -s /proc/self/fd $rootDir/root/dev/fd
	$bb ln -s /proc/self/fd/0 $rootDir/root/dev/stdin
	$bb ln -s /proc/self/fd/1 $rootDir/root/dev/stdout
	$bb ln -s /proc/self/fd/2 $rootDir/root/dev/stderr
	addDevices $rootDir $(bb=$bb $g_configCmd getCurVal $rootDir availableDevices)

	# only these should be writable
	$bb mount -o bind,rw $rootDir/root/home $rootDir/root/home
	$bb mount -o bind,rw $rootDir/root/var $rootDir/root/var
	$bb mount -o bind,rw $rootDir/root/tmp $rootDir/root/tmp

	mountMany $rootDir/root "rw,noexec" $(printf "%s" "$(bb=$bb $g_configCmd getCurVal $rootDir devMountPoints)" | filterCommentedLines | expandSafeValues $actualUser $userUID $userGID)
	mountMany $rootDir/root "ro,exec" $(printf "%s" "$(bb=$bb $g_configCmd getCurVal $rootDir roMountPoints)" | filterCommentedLines | expandSafeValues $actualUser $userUID $userGID)
	mountMany $rootDir/root "defaults" $(printf "%s" "$(bb=$bb $g_configCmd getCurVal $rootDir rwMountPoints)" | filterCommentedLines | expandSafeValues $actualUser $userUID $userGID)

	handleDirectMounts $rootDir $actualUser $userUID $userGID

	$bb mount -o private,bind,remount,ro $rootDir/root
	$bb mount -o bind,ro,remount $rootDir/root/dev

	if [ "$(bb=$bb $g_configCmd getCurVal $rootDir mountSys)" = "true" ]; then
		if ! bb=$bb $g_utilsCmd isPrivileged && [ "$(bb=$bb $g_configCmd getCurVal $rootDir setNetAccess)" = "true" ]; then
			echo "Could not mount the /sys directory. As an unprivileged user, the only way this is possible is by disabling setNetAccess. Or you can always run this jail as a privileged user." >&2
		else
			$bb mount -tsysfs none $rootDir/root/sys
		fi
	fi
}

isUserNamespaceSupported() {
	if echo $g_unshareSupport | $bb grep -q 'U'; then
		if [ -e /proc/sys/kernel/unprivileged_userns_clone ]; then
			if [ "$($bb cat /proc/sys/kernel/unprivileged_userns_clone)" = "0" ]; then
				return 1
			else
				return 0
			fi
		else
			return 0
		fi
	else
		return 1
	fi
}

prepareChrootCore() {
	local rootDir=$1
	local unshareArgs=""
	local preUnshare=""
	local chrootCmd="$nsBB env - $g_baseEnv JT_LOCATION=$rootDir JT_VERSION=$(bb=$bb $g_configCmd getDefaultVal $rootDir jailVersion) JT_JAILPID=$$ sh -c 'while :; do $nsBB sleep 9999; done'"

	if bb=$bb $g_utilsCmd isPrivileged && isUserNamespaceSupported && [ "$(bb=$bb $g_configCmd getCurVal $rootDir realRootInJail)" = "false" ]; then
		preUnshare="$bb chpst -u $(bb=$bb $g_utilsCmd getBaseUserCredentials $rootDir)"
		unshareArgs="-r"
	elif ! bb=$bb $g_utilsCmd isPrivileged && isUserNamespaceSupported; then # unprivileged
		unshareArgs="-r"
		g_unshareSupport=$(echo "$g_unshareSupport" | $bb sed -e 's/U//g')
	else # ! isUserNamespaceSupported or $realRootInJail = "true"
		unshareArgs=""
		g_unshareSupport=$(echo "$g_unshareSupport" | $bb sed -e 's/U//g')
	fi # ! isUserNamespaceSupported or $realRootInJail = "true"

	if [ "$jailNet" = "true" ]; then
		if bb=$bb $g_utilsCmd isPrivileged || (! bb=$bb $g_utilsCmd isPrivileged && [ "$(bb=$bb $g_configCmd getCurVal $rootDir setNetAccess)" = "false" ]); then
			unshareArgs="$unshareArgs -n"
		fi
	fi

	chrootCmd="touch /var/run/.loadCoreDone; $chrootCmd"

	if [ "$(bb=$bb $g_configCmd getCurVal $rootDir realRootInJail)" = "true" ]; then
		chrootCmd="$nsBB sleep 1; $chrootCmd"
	fi

	# ensure these files are owned by the user
	# we don't touch those that already exist, fix them yourself
	[ ! -e $rootDir/$g_firewallInstr ] && $uBB touch $rootDir/$g_firewallInstr
	if [ ! -e $rootDir/run/daemon.log ]; then # this file is special, it's created by the superscript
		$uBB touch $rootDir/run/daemon.log
	elif [ "$($bb stat -c %U $rootDir/run/daemon.log)" != "$(bb=$bb $g_utilsCmd getBaseUserUID $rootDir)" ]; then
		$bb chown $(bb=$bb $g_utilsCmd getBaseUserUID $rootDir) $rootDir/run/daemon.log
	fi
	[ ! -e $rootDir/run/innerCoreLog ] && $uBB touch $rootDir/run/innerCoreLog

	[ -e $rootDir/root/var/run/.loadCoreDone ] && $bb rm $rootDir/root/var/run/.loadCoreDone

	innerCoreCreator=$($bb cat - << EOF
export BB="$bb";
export bb="$bb";
export JT_SHOWER="$shower";
export JT_RUNNER="$runner";
$runner jt_jailLib_template initializeCoreJail $rootDir $(bb=$bb $g_utilsCmd getActualUser $rootDir) \
	$(bb=$bb $g_utilsCmd getBaseUserUID $rootDir) $(bb=$bb $g_utilsCmd getBaseUserGID $rootDir)\";
cd $rootDir/root;
$bb pivot_root . $rootDir/root/root;
exec $nsBB chroot . /bin/sh -c "$nsBB umount -l /root; \
	$nsBB setpriv --bounding-set $(bb=$bb $g_configCmd getCurVal $rootDir chrootPrivileges) \
	$chrootCmd"
EOF
)
	# this is the core jail instance being run in the background
	(
		$preUnshare $bb unshare -f $unshareArgs ${g_unshareSupport} \
			-- $bb setpriv --bounding-set $(bb=$bb $g_configCmd getCurVal $rootDir corePrivileges) \
				$bb sh -c "$innerCoreCreator" 2>$rootDir/run/innerCoreLog
	) &
	g_innerNSpid=$!
	start="$(bb=$bb $g_utilsCmd getUtime)"
	if bb=$bb $g_utilsCmd waitUntilFileAppears "$rootDir/root/var/run/.loadCoreDone" 15; then
		g_innerNSpid=$($bb pgrep -P $g_innerNSpid)
	else
		echo "Timed out waiting for the core inner namespace session to start" >&2
		g_innerNSpid=""
	fi
	local end="$(bb=$bb $g_utilsCmd getUtime)"

	if [ "$g_innerNSpid" = "" ] || ! $bb ps | $bb grep -q "^ *$g_innerNSpid "; then
		echo "Creating the inner namespace session failed, bailing out" >&2
		return 1
	else
		echo "Core creation took $(echo "$end - $start" | $bb bc -l) seconds" >> $rootDir/run/innerCoreLog
	fi

	return 0
}

prepareChrootNetworking() {
	local rootDir=$1

	if [ "$jailNet" = "true" ]; then
		# loopback device is activated
		execNS $rootDir $nsBB ip link set up lo

		if [ "$(bb=$bb $g_configCmd getCurVal $rootDir createBridge)" = "true" ]; then
			# NOTE that it is perfectly possible to create a bridge unprivileged
			# setting up the bridge
			execNS $rootDir $nsBB brctl addbr $(bb=$bb $g_configCmd getCurVal $rootDir bridgeName)
			execNS $rootDir $nsBB ip addr add $(bb=$bb $g_configCmd getCurVal $rootDir bridgeIp)/$(bb=$bb $g_configCmd getCurVal $rootDir bridgeIpBitmask) dev $(bb=$bb $g_configCmd getCurVal $rootDir bridgeName) scope link
			execNS $rootDir $nsBB ip link set up $(bb=$bb $g_configCmd getCurVal $rootDir bridgeName)
		fi

		if [ "$networking" = "true" ]; then
			local externalIp=$(bb=$bb $g_configCmd getCurVal $rootDir extIp)
			local ipInt=$(echo $externalIp | $bb sed -e 's/^\(.*\)\.[0-9]*$/\1\./')2
			local vethExternal=$(bb=$bb $g_configCmd getCurVal $rootDir vethExt)
			local vethInternal=$(bb=$bb $g_configCmd getCurVal $rootDir vethInt)

			$bb ip link add $vethExternal type veth peer name $vethInternal
			$bb ip link set $vethExternal up
			$bb ip link set $vethInternal netns $g_innerNSpid
			execNS $rootDir $nsBB ip link set $vethInternal up

			execNS $rootDir $nsBB ip addr add $ipInt/$(bb=$bb $g_configCmd getCurVal $rootDir ipIntBitmask) dev $vethInternal scope link

			$bb ip addr add $externalIp/$(bb=$bb $g_configCmd getCurVal $rootDir extIpBitmask) dev $vethExternal scope link
			$bb ip link set $vethExternal up
			execNS $rootDir $nsBB ip route add default via $externalIp dev $vethInternal proto kernel src $ipInt

			local networkInterface=$(bb=$bb $g_configCmd getCurVal $rootDir netInterface)
			if [ "$(bb=$bb $g_configCmd getCurVal $rootDir setNetAccess)" = "true" ] && [ "$networkInterface" != "" ]; then
				if [ "$networkInterface" = "auto" ]; then
					networkInterface=$($bb ip route | $bb grep '^default' | $bb sed -e 's/^.* dev \([^ ]*\) .*$/\1/')
				fi

				if [ "$networkInterface" = "" ]; then
					echo "Could not find a default route network interface, is the network up?" >&2
					return 1
				fi

				bb=$bb $runner jt_firewall firewall $g_firewallInstr "external" snat $networkInterface $vethExternal $ipInt $(bb=$bb $g_configCmd getCurVal $rootDir ipIntBitmask)
			fi
		fi

		# do note that networking is not necessary for this to work.
		local joinBridgeFromOtherJail=$(bb=$bb $g_configCmd getCurVal $rootDir joinBridgeFromOtherJail)
		if [ "$joinBridgeFromOtherJail" != "" ]; then
			local entries="$(printf "%s" "$joinBridgeFromOtherJail" | filterCommentedLines | expandSafeValues2 '\\$actualUser' $(bb=$bb $g_utilsCmd getActualUser $rootDir))"
			oldIFS="$IFS"
			IFS="
			"
			for entry in $entries; do
				IFS=$oldIFS
				joinBridgeByJail $rootDir $entry || return 1
			done
			IFS=$oldIFS
		fi

		local joinBridge=$(bb=$bb $g_configCmd getCurVal $rootDir joinBridge)
		if [ "$joinBridge" != "" ]; then
			oldIFS="$IFS"
			IFS="
			"
			for entry in $(printf "%s" "$joinBridge" | filterCommentedLines); do
				IFS=$oldIFS
				joinBridge $rootDir $entry || return 1
			done
			IFS=$oldIFS
		fi
	fi

	return 0
}

prepareChroot() {
	local rootDir=$1

	# importing utils.sh
	bb=$bb $runner jt_utils prepareScriptInFifo "$rootDir/run/instrFileLibJT" "utils.sh" "jt_utils" &
	if ! bb=$bb $runner jt_utils waitUntilFileAppears "$rootDir/run/instrFileLibJT" 2 1; then
		echo "Timed out waiting for FIFO to be created" >&2
		return 1
	fi

	. $rootDir/run/instrFileLibJT
	g_utilsCmd=""

	# importing config.sh
	bb=$bb $runner jt_utils prepareScriptInFifo "$rootDir/run/instrFileLibJT" "config.sh" "jt_config" &
	if ! bb=$bb $runner jt_utils waitUntilFileAppears "$rootDir/run/instrFileLibJT" 2 1; then
		echo "Timed out waiting for FIFO to be created" >&2
		return 1
	fi

	. $rootDir/run/instrFileLibJT
	g_configCmd=""

	if ! isUserNamespaceSupported && ! bb=$bb $g_utilsCmd isPrivileged; then
		echo "User namespace support is currently disabled." >&2
		echo "This has to be enabled to support starting a jail unprivileged." >&2
		printf "Until the change is done, creating a jail requires privileges.\n\n" >&2
		echo "Please do (as root) :" >&2
		printf "\techo 1 > /proc/sys/kernel/unprivileged_userns_clone\n\n" >&2
		echo "or find the method suitable for your distribution to" >&2
		echo "activate unprivileged user namespace clone." >&2
		return 1
	fi

	if ! bb=$bb $g_utilsCmd isPrivileged; then
		echo "You are running this script unprivileged, most features will not work" >&2
		if [ "$networking" = "true" ]; then
			networking="false"
			echo "Unprivileged jails do not support the setting networking, turning it off" >&2
		fi
	else
		touch $rootDir/run/.isPrivileged
	fi

	if [ "$g_netNS" = "false" ] && [ "$jailNet" = "true" ]; then
		jailNet="false"
		echo "jailNet is set to false automatically as it needs network namespace support which is not available." >&2
	fi

	if [ "$($bb cat /proc/sys/net/ipv4/ip_forward)" = "0" ] && bb=$bb $g_utilsCmd isPrivileged && [ "$(bb=$bb $g_configCmd getCurVal $rootDir setNetAccess)" = "true" ]; then
		networking="false"
		echo "The ip_forward bit in /proc/sys/net/ipv4/ip_forward is disabled. This has to be enabled to get handled network support. Setting networking to false." >&2
		echo "\tPlease do (as root) : echo 1 > /proc/sys/net/ipv4/ip_forward  or find the method suitable for your distribution to activate IP forwarding." >&2
	fi

	if ! bb=$bb $g_utilsCmd isPrivileged && [ "$g_netNS" = "true" ] && isStartedAsPrivileged $rootDir; then
		g_nsenterSupport="$g_nsenterSupport -n";
	fi

	if bb=$bb $g_utilsCmd isJailRunning $rootDir; then
		echo "This jail was already started, bailing out." >&2
		return 1
	else
		if [ -e $rootDir/run/jail.pid ]; then
			echo "removing dangling run/jail.pid" >&2
			$bb rm $rootDir/run/jail.pid
		fi

		if [ -e $rootDir/run/ns.pid ]; then
			echo "removing dangling run/ns.pid" >&2
			$bb rm $rootDir/run/ns.pid
		fi
	fi

	prepareChrootCore $rootDir || return 1

	echo $g_innerNSpid > $rootDir/run/ns.pid
	$bb chmod o+r $rootDir/run/ns.pid

	prepareChrootNetworking $rootDir || return 1

	local firewallRules=$(bb=$bb $g_configCmd getCurVal $rootDir firewallRules | filterCommentedLines)
	if [ "$firewallRules" != "" ]; then
		if ! bb=$bb $g_utilsCmd isPrivileged; then
			echo "Unprivileged jails can't setup firewall rules" >&2
		else
			local vethInt=$(bb=$bb $g_configCmd getCurVal $rootDir vethInt)
			local vethExt=$(bb=$bb $g_configCmd getCurVal $rootDir vethExt)
			local externalIp=$(bb=$bb $g_configCmd getCurVal $rootDir extIp)
			local ipInt=$(echo $externalIp | $bb sed -e 's/^\(.*\)\.[0-9]*$/\1\./')2
			oldIFS="$IFS"
			IFS="
			"
			for entry in $(printf "%s" "$firewallRules"); do
				IFS=$oldIFS

				entry=$(echo $entry | sed -e "s/\$vethInt/$vethInt/g" \
					-e "s/\$vethExt/$vethExt/g" \
					-e "s/\$ipInt/$ipInt/g")

				bb=$bb $runner jt_firewall firewall $g_firewallInstr $entry
			done
			IFS=$oldIFS
		fi
	fi

	return 0
}

runShell() {
	local primaryShell="false"
	local daemonize="false"
	local preUnshare=""
	OPTIND=0
	while getopts dp f 2>/dev/null ; do
		case $f in
			p) local primaryShell="true";;
			d) local daemonize="true";;
		esac
	done
	[ $(($OPTIND > 1)) = 1 ] && shift $($bb expr $OPTIND - 1)
	local rootDir=$1
	local nsPid=$2
	local curArgs=""
	shift 2

	local arg=""
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

	if [ "$primaryShell" = "true" ]; then
		echo $$ > $rootDir/run/jail.pid
		$bb chmod o+r $rootDir/run/jail.pid
	fi

	if [ "$daemonize" = "true" ]; then
		if [ "$curArgs" = "" ]; then
			curArgs="sh -c 'while :; do $nsBB sleep 9999; done'"
		else
			curArgs=$(printf "%s" "$curArgs" | $bb sed -e 's/\x27/"/g') # replace all ' with "
			curArgs="sh -c '${curArgs}; while :; do $nsBB sleep 9999; done'"
		fi
	fi

	local unshareArgs="-U --map-user=$(bb=$bb $g_utilsCmd getBaseUserUID $rootDir) --map-group=$(bb=$bb $g_utilsCmd getBaseUserGID $rootDir)"
	if bb=$bb $g_utilsCmd isPrivileged; then
		[ "$(bb=$bb $g_configCmd getCurVal $rootDir realRootInJail)" = "true" ] && unshareArgs=""
	else
		[ "$(bb=$bb $g_configCmd getCurVal $rootDir realRootInJail)" = "true" ] && unshareArgs="-r"
		if isStartedAsPrivileged $rootDir && [ "$g_netNS" = "true" ] && [ "$jailNet" = "true" ]; then
			g_nsenterSupport="$g_nsenterSupport -n";
		fi
	fi

	execRemNS $rootDir $nsPid $nsBB sh -c "exec $nsBB unshare $unshareArgs $nsBB env - $g_baseEnv $curArgs"

	return $?
}

stopChroot() {
	local rootDir=$1

	[ -e $rootDir/run/isStopping ] && return 0


	if ! bb=$bb $g_utilsCmd isPrivileged; then
		if isStartedAsPrivileged $rootDir; then
			echo "This jail was started as root and it needs to be stopped as root as well."
			return 1
		fi
	fi

	if [ ! -e $rootDir/run/ns.pid ]; then
		echo "This jail is not running, can't stop it. Bailing out." >&2
		return 1
	fi
	g_innerNSpid="$($bb cat $rootDir/run/ns.pid)"

	if [ "$g_innerNSpid" = "" ] || [ "$($bb pstree $g_innerNSpid)" = "" ]; then
		echo "This jail doesn't seem to be running anymore, please check lsns to confirm" >&2
		return 1
	fi

	if [ "$jailNet" = "true" ]; then
		if [ "$(bb=$bb $g_configCmd getCurVal $rootDir createBridge)" = "true" ]; then
			execNS $rootDir $nsBB ip link set down $(bb=$bb $g_configCmd getCurVal $rootDir bridgeName)
			execNS $rootDir $nsBB brctl delbr $(bb=$bb $g_configCmd getCurVal $rootDir bridgeName)
		fi
	fi

	local oldIFS="$IFS"
	IFS="
	"
	# removing the firewall rules inserted into the instructions file
	# TODO this part could be made in a manner that is much nicer and more secure than
	# using 'eval'
	for cmd in $(IFS=$oldIFS; bb=$bb $runner jt_firewall cmdCtl "$rootDir/$g_firewallInstr" list); do
		IFS="$oldIFS" # we set back IFS for remCmd
		remCmd=$(printf "%s" "$cmd" | $bb sed -e 's@firewall \(.*\) \(in\|ex\)ternal \(.*\)$@firewall \1 \2ternal -d \3@')

		eval bb=$bb $runner jt_firewall $remCmd
	done
	IFS=$oldIFS

	if [ -e $rootDir/run/ns.pid ]; then
		echo "" > $rootDir/run/isStopping
		kill -9 $g_innerNSpid >/dev/null 2>/dev/null
		if [ "$?" = "0" ]; then
			$bb rm -f $rootDir/run/ns.pid
			$bb rm -f $rootDir/run/jail.pid
		fi
	fi
	$bb rm $rootDir/run/isStopping

	[ -e $rootDir/run/.isPrivileged ] && $bb rm -f $rootDir/run/.isPrivileged

	return 0
}

execNS() {
	local rootDir=$1
	shift
	execRemNS $rootDir $g_innerNSpid "$@"
}

execRemNS() {
	local rootDir=$1
	local nsPid=$2
	shift 2
	#echo "NS [$nsPid] -- args : $g_nsenterSupport exec : \"$@\"" >&2
	extraParams=""
	preNSenter=""
	if bb=$bb $g_utilsCmd isPrivileged; then
		if [ "$(bb=$bb $g_configCmd getCurVal $rootDir realRootInJail)" = "false" ]; then
			extraParams="-U"
			preNSenter="$bb chpst -u $(bb=$bb $g_utilsCmd getBaseUserCredentials $rootDir)"
		fi
	fi
	$preNSenter $bb nsenter --preserve-credentials $extraParams $g_nsenterSupport -t $nsPid -- "$@"
	return $?
}

if [ "$IS_RUNNING" = "1" ]; then
	IS_RUNNING=0
	cmd=$1
	shift
	case $cmd in
		initializeCoreJail)
			rootDir="$1"

			# importing utils.sh
			bb=$bb $runner jt_utils prepareScriptInFifo "$rootDir/run/instrFileLibJT" "utils.sh" "jt_utils" &
			if ! bb=$bb $runner jt_utils waitUntilFileAppears "$rootDir/run/instrFileLibJT" 2 1; then
				echo "Timed out waiting for FIFO to be created" >&2
				return 1
			fi

			. $rootDir/run/instrFileLibJT
			g_utilsCmd=""

			# importing config.sh
			prepareScriptInFifo "$rootDir/run/instrFileLibJT" "config.sh" "jt_config" &
			if ! waitUntilFileAppears "$rootDir/run/instrFileLibJT" 2 1; then
				echo "Timed out waiting for FIFO to be created" >&2
				return 1
			fi

			. $rootDir/run/instrFileLibJT
			g_configCmd=""

			initializeCoreJail "$@"
			exit 0
		;;
	esac
fi
