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

# substring offset <optional length> string
# cuts a string at the starting offset and wanted length.
substring() {
	local init=$1; shift
	if [ "$2" != "" ]; then toFetch="\(.\{$1\}\).*"; shift; else local toFetch="\(.*\)"; fi
	echo "$1" | $bb sed -e "s/^.\{$init\}$toFetch$/\1/"
}

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
	actualUser=$($bb stat -c %U $ownPath/jailLib.sh)
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

nsenterSupport=$(echo "$unshareSupport" | $bb sed -e 's/^-//' | $bb sed -e 's/\(.\)/-\1 /g')
if [ "$netNS" = "true" ]; then
	if [ "$jailNet" = "false" ] || ([ "$privileged" = "0" ] && [ "$disableUnprivilegedNetworkNamespace" = "true" ]); then
		:
	else
		nsenterSupport="$nsenterSupport -n";
	fi
fi

if [ "$privileged" = "1" ]; then
	nsenterSupport="$(echo $nsenterSupport | $bb sed -e 's/-U//g')"
fi

if [ "$privileged" = "0" ]; then
	[ "$setNetAccess" = "true" ] && echo "Can't have setNetAccess for an unprivileged jail. Setting setNetAccess to false." >&2 && setNetAccess="false"

	if [ "$userNS" != "true" ]; then
		echo "The user namespace is not supported. Can't start an unprivileged jail without it, bailing out." >&2
		exit 1
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

if [ "$($bb cat /proc/sys/net/ipv4/ip_forward)" = "0" ]; then
	networking=false
	echo "The ip_forward bit in /proc/sys/net/ipv4/ip_forward is disabled. This has to be enabled to get handled network support. Setting networking to false." >&2
	echo "\tPlease do (as root) : echo 1 > /proc/sys/net/ipv4/ip_forward  or find the method suitable for your distribution to activate IP forwarding." >&2
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

parseArgs() {
	OPTIND=0
	local silentMode="false"
	local oldIFS=$IFS
	while getopts s f 2>/dev/null; do
		case $f in
			s) local silentMode="true";;
		esac
	done
	[ $(($OPTIND > 1)) = 1 ] && shift $($bb expr $OPTIND - 1)
	local title="$1"
	local validArguments="$(printf "%s" "$2" | $bb sed -e "s/\('[^']*'\) /\1\n/g" | $bb sed -e "/^'/ b; s/ /\n/g" | $bb sed -e "s/'//g")"
	shift 2

	IFS="
	"
	for elem in $(printf "%s" "$validArguments"); do
		if [ "$1" = "" ]; then
			[ "$silentMode" = "false" ] && echo "$title : Missing the required argument '$elem'" >&2
			IFS="$oldIFS"
			return 1
		fi
		shift
	done
	IFS="$oldIFS"
	return 0
}

# This function is meant to interface with an instructions file.
# the instructions file contains data separated by semicolons, each are called command.
# we can check if a command is present, remove and add them. We can also output a version
# that is fitting to be looped.
cmdCtl() {
	local file=$1
	local cmd=$2
	shift 2
	local result=""

	IFS=" "

	exists() { printf "%s" "$2" | $bb grep "\(^\|;\)$1;" >/dev/null 2>/dev/null;}
	remove() { exists "$1" "$2" && (printf "%s" "$2" | $bb sed -e "s@\(^\|;\)$1;@\1@") || printf "%s" "$2";}
	add() { exists "$1" "$2" && printf "%s" "$2" || printf "%s%s;" "$2" "$1";}
	list() { printf "%s" "$1" | $bb sed -e 's@;@\n@g';}


	if [ ! -e $file ]; then
		if [ ! -d $($bb dirname $file) ]; then
			$bb mkdir -p $($bb dirname $file)
		fi
		$bb touch $file
	fi

	case $cmd in
		exists) exists "$1" "$($bb cat $file)" ;;
		remove) remove "$1" "$($bb cat $file)" > $file ;;
		add) add "$1" "$($bb cat $file)" > $file ;;
		list) list "$($bb cat $file)" ;;
		*)
			echo "Invalid command entered" >&2
			return 1
		;;
	esac
}

mountSingle() {
	local rootDir="$1"
	local src="$2"
	local dst="$3"
	shift 3

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
				$bb sh -c "$bb mountpoint $rootDir/$mount >/dev/null 2>/dev/null || $bb mount -o $mountOps --bind $mount $rootDir/$mount"
				# gotta remount for the options to take effect
				$bb sh -c "$bb mountpoint $rootDir/$mount >/dev/null 2>/dev/null || $bb mount -o $mountOps,remount --bind $rootDir/$mount $rootDir/$mount"
			else # isOutput = true
				result="$result if [ ! -d \"$rootDir/$mount\" ]; then $(cmkdir -e -m 755 $rootDir/$mount) fi;"
				result="$result $bb mountpoint $rootDir/$mount >/dev/null 2>/dev/null || $bb mount -o $mountOps --bind $mount $rootDir/$mount;"
				# gotta remount for the options to take effect
				result="$result $bb mountpoint $rootDir/$mount >/dev/null 2>/dev/null || $bb mount -o $mountOps,remount --bind $rootDir/$mount $rootDir/$mount;"
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
		return
	fi

	$bb ip link add $vethExternal type veth peer name $vethInternal
	$bb ip link set $vethExternal up
	$bb ip link set $vethInternal netns $innerNSpid
	execNS $nsBB ip link set $vethInternal up

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
		execRemNS $externalNetnsId $bb ip link set $vethExternal up
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
		return
	fi

	if [ -d $jailLocation/root ] && [ -d $jailLocation/run ] && [ -f $jailLocation/startRoot.sh ] && [ -f $jailLocation/rootCustomConfig.sh ]; then
		local defConfPath=$jailLocation/rootDefaultConfig.sh
		local confPath=$jailLocation/rootCustomConfig.sh

		local neededConfig="$($bb cat $confPath | $bb sed -ne '/^jailName=/ p; /^createBridge=/ p; /^bridgeName=/ p;')"
		for cfg in jailName createBridge bridgeName; do
			tempVal="$(printf "%s" "$neededConfig" | $bb sed -ne "/^$cfg/ p" | $bb sed -e 's/#.*//' | $bb sed -e 's/^[^=]\+=\(.*\)$/\1/' | $bb sed -e 's/${\([^:]\+\):/${rem\1:/' -e 's/$\([^{(]\+\)/$rem\1/')"

			if [ "$tempVal" = "" ] && [ -e $defConfPath ]; then
				local neededDefConfig="$($bb cat $defConfPath | $bb sed -ne '/^jailName=/ p; /^createBridge=/ p; /^bridgeName=/ p;')"
				tempVal="$(printf "%s" "$neededDefConfig" | $bb sed -ne "/^$cfg/ p" | $bb sed -e 's/#.*//' | $bb sed -e 's/^[^=]\+=\(.*\)$/\1/' | $bb sed -e 's/${\([^:]\+\):/${rem\1:/' -e 's/$\([^{(]\+\)/$rem\1/')"
			fi

			if [ "$tempVal" = "" ]; then
				echo "joinBridgeByJail - Error - Unable to process the remote jail's information" >&2
				exit 1
			fi

			eval "local rem$cfg"=$tempVal
		done

		if [ "$remcreateBridge" != "true" ]; then
			echo "joinBridgeByJail: This jail does not have a bridge, aborting joining." >&2
			return
		fi

		if [ ! -e "$jailLocation/run/ns.pid" ]; then
			echo "joinBridgeByJail: This jail at \`$jailLocation' is not currently started, aborting joining." >&2
			return
		fi
		remnetnsId=$($bb cat $jailLocation/run/ns.pid)

		# echo "Attempting to join bridge $rembridgeName on jail $remjailName with net ns $remnetnsId"
		joinBridge "$isDefaultRoute" "$remjailName" "$jailName" "$remnetnsId" "$rembridgeName" "$internalIpNum"
	else
		echo "Supplied jail path is not a valid supported jail." >&2
	fi
}

# jailLocation - The jail that hosts a bridge you wish to disconnect from.
leaveBridgeByJail() {
	local jailLocation=$1

	if [ -d $jailLocation/root ] && [ -d $jailLocation/run ] && [ -f $jailLocation/startRoot.sh ] && [ -f $jailLocation/rootCustomConfig.sh ]; then
		local confPath=$jailLocation/rootCustomConfig.sh

		local neededConfig=$($bb cat $confPath | $bb sed -ne '/^jailName=/ p; /^createBridge=/ p; /^bridgeName=/ p;')
		for cfg in jailName createBridge bridgeName; do
			eval "local rem$cfg"="$(printf "%s" "$neededConfig" | $bb sed -ne "/^$cfg/ p" | $bb sed -e 's/#.*//' | $bb sed -e 's/^[^=]\+=\(.*\)$/\1/' | $bb sed -e 's/${\([^:]\+\):/${rem\1:/' -e 's/$\([^{(]\+\)/$rem\1/')"
		done

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

# don't use this function directly, use either internalFirewall or externalFirewall
# Internal is for the jail itself
# External is the host system's firewall
firewall() {
	if [ "$privileged" = "0" ]; then
		return
	fi
	local rootDir=''
	local fwType=''
	local singleRunMode="false" # it means this command should not be accounted in the firewall instructions file
	local mode="create"
	local arguments=''
	local fwCmd=''
	local cmd=''
	local upstream=''
	local downstream=''
	if [ "$jailNet" = "true" ]; then
		rootDir=$1
		fwType=$2
		shift 2
		OPTIND=0
		while getopts dsc f 2>/dev/null ; do
			case $f in
				d) mode="delete";;
				s) singleRunMode="true";;
				c) mode="check";;
			esac
		done
		[ $(($OPTIND > 1)) = 1 ] && shift $($bb expr $OPTIND - 1)
		cmd=$1
		case "$fwType" in
			"internal")
				fwCmd="execNS $nsBB $iptablesBin"
			;;

			"external")
				fwCmd="$iptablesBin"
			;;

			*)
				echo "Don't call this function directly, use 'externalFirewall' or 'internalFirewall' instead." >&2
				return
			;;
		esac
		shift
		arguments="$@"
		fwFile="$rootDir/$firewallInstr"
		[ ! -e $fwFile ] && ($bb touch $fwFile; $bb chmod o+r $fwFile)

		case $mode in
			create)
				if [ "$singleRunMode" = "false" ]; then
					cmdCtl "$fwFile" exists "firewall $rootDir $fwType $cmd $arguments" && return 0
				fi # not singleRunMode
			;;

			delete)
				if [ "$singleRunMode" = "false" ]; then
					cmdCtl "$fwFile" exists "firewall $rootDir $fwType $cmd $arguments" || return 0
				fi # not singleRunMode
			;;
		esac
			

		case "$cmd" in
			"blockAll")
				parseArgs "blockAll" "" $arguments || return 1
				case $mode in
					create)
						t="-A"
					;;

					delete)
						t="-D"
					;;

					check)
						t="-C"
					;;
				esac

				# block all tcp packets except those that are established
				# and related (this is appended at the bottom)
				$fwCmd $t INPUT -p tcp -m tcp --dport 1:65535 -m state \! --state ESTABLISHED,RELATED -j REJECT
				[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				$fwCmd $t INPUT -p udp -m udp --dport 1:65535 -m state \! --state ESTABLISHED,RELATED -j REJECT
				[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				# block all outgoing packets except established ones
				$fwCmd $t OUTPUT -p all -m state \! --state ESTABLISHED,RELATED -j REJECT
				[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
			;;

			"openPort")
				parseArgs "openPort" "'interface from' 'interface to' 'tcp or udp' 'destination port'" $arguments || return 1
				case $mode in
					create)
						# "inserted" so they are before the reject rules
						t="-I"
					;;

					delete)
						t="-D"
					;;

					check)
						t="-C"
					;;
				esac


				# request ext -> int:port
				$fwCmd $t OUTPUT -o $1 -p $3 --dport $4 -j ACCEPT
				[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				$fwCmd $t OUTPUT -o $2 -p $3 --sport $4 -j ACCEPT
				[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				$fwCmd $t INPUT -i $2 -p $3 --dport $4 -j ACCEPT
				[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				# response int:port -> ext
				$fwCmd $t INPUT -i $1 -p $3 --sport $4 -j ACCEPT
				[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
			;;

			"openTcpPort")
				parseArgs "openTcpPort" "'interface from' 'interface to' 'destination port'" $arguments || return 1
				case $mode in
					create)
						firewall $rootDir $fwType -s "openPort" $1 $2 "tcp" $3
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;

					delete)
						firewall $rootDir $fwType -d -s "openPort" $1 $2 "tcp" $3
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;

					check)
						firewall $rootDir $fwType -c -s "openPort" $1 $2 "tcp" $3
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;
				esac
			;;

			"openUdpPort")
				parseArgs "openUdpPort" "'interface' 'destination port'" $arguments || return 1
				parseArgs "openUdpPort" "'interface from' 'interface to' 'destination port'" $arguments || return 1
				case $mode in
					create)
						firewall $rootDir $fwType -s "openPort" $1 $2 "udp" $3
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;

					delete)
						firewall $rootDir $fwType -d -s "openPort" $1 $2 "udp" $3
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;

					check)
						firewall $rootDir $fwType -c -s "openPort" $1 $2 "udp" $3
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;
				esac
			;;

			"allowConnection")
				parseArgs "allowConnection" "'tcp or udp' 'output interface' 'destination address' 'destination port'" $arguments || return 1
				case $mode in
					create)
						t="-I"
					;;

					delete)
						t="-D"
					;;

					check)
						t="-C"
					;;
				esac

				$fwCmd $t OUTPUT -p $1 -o $2 -d $3 --dport $4 -j ACCEPT >/dev/null 2>/dev/null
			;;

			"allowTcpConnection")
				parseArgs "allowTcpConnection" "'output interface' 'destination address' 'destination port'" $arguments || return 1
				case $mode in
					create)
						firewall $rootDir $fwType -s "allowConnection" tcp $1 $2 $3
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;

					delete)
						firewall $rootDir $fwType -d -s "allowConnection" tcp $1 $2 $3
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;

					check)
						firewall $rootDir $fwType -c -s "allowConnection" tcp $1 $2 $3
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;
				esac
			;;

			"allowUdpConnection")
				parseArgs "allowUdpConnection" "'output interface' 'destination address' 'destination port'" $arguments || return 1
				case $mode in
					create)
						firewall $rootDir $fwType -s "allowConnection" udp $1 $2 $3
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;

					delete)
						firewall $rootDir $fwType -d -s "allowConnection" udp $1 $2 $3
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;

					check)
						firewall $rootDir $fwType -c -s "allowConnection" udp $1 $2 $3
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;
				esac
			;;

			"dnat")
				parseArgs "dnat" "'tcp or udp' 'input interface' 'output interface' 'source port' 'destination address' 'destination port'" $arguments || return 1
				case $mode in
					create)
						t="-A"
						t2="-I"
					;;

					delete)
						t="-D"
						t2="-D"
					;;

					check)
						t="-C"
						t2="-C"
					;;
				esac
				$fwCmd -t nat $t PREROUTING -i $2 -p $1 -m $1 --dport $4 -j DNAT --to-destination $5:$6
				[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				$fwCmd -t filter $t2 FORWARD -p $1 -i $2 -o $3 -m state --state NEW,ESTABLISHED,RELATED -m $1 --dport $6 -j ACCEPT
				[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				$fwCmd -t filter $t2 FORWARD -p $1 -i $3 -o $2 -m state --state ESTABLISHED,RELATED -j ACCEPT
				[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
			;;

			"dnatTcp")
				parseArgs "dnatTcp" "'input interface' 'output interface' 'source port' 'destination address' 'destination port'" $arguments || return 1
				case $mode in
					create)
						firewall $rootDir $fwType -s "dnat" tcp $1 $2 $3 $4 $5
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;

					delete)
						firewall $rootDir $fwType -d -s "dnat" tcp $1 $2 $3 $4 $5
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;

					check)
						firewall $rootDir $fwType -c -s "dnat" tcp $1 $2 $3 $4 $5
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;
				esac
			;;

			"dnatUdp")
				parseArgs "dnatUdp" "'input interface' 'output interface' 'source port' 'destination address' 'destination port'" $arguments || return 1
				case $mode in
					create)
						firewall $rootDir $fwType -s "dnat" udp $1 $2 $3 $4 $5
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;

					delete)
						firewall $rootDir $fwType -d -s "dnat" udp $1 $2 $3 $4 $5
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;

					check)
						firewall $rootDir $fwType -c -s "dnat" udp $1 $2 $3 $4 $5
						[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
					;;
				esac
			;;

			"snat")
				parseArgs "snat" "'the interface connected to the outbound network' 'the interface from which the packets originate'" $arguments || return 1
				upstream=$1 # the snat goes through here
				downstream=$2 # this is the device to snat

				baseAddr=$(echo $ipInt | $bb sed -e 's/\.[0-9]*$/\.0/') # convert 192.168.xxx.xxx to 192.168.xxx.0
				case $mode in
					create)
						t="-N"
						t2="-A"
						t3="-I"
					;;

					delete)
						t="-X"
						t2="-D"
						t3="-D"
					;;

					check)
						t="-C"
						t2="-C"
						t3="-C"
					;;
				esac

				if [ "$mode" = "create" ]; then
					$fwCmd -t nat $t ${upstream}_${downstream}_masq
					[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				fi

				$fwCmd -t nat $t2 POSTROUTING -o $upstream -j ${upstream}_${downstream}_masq
				[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				$fwCmd -t nat $t2 ${upstream}_${downstream}_masq -s $baseAddr/$ipIntBitmask -j MASQUERADE
				[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1

				$fwCmd -t filter $t3 FORWARD -i $downstream -o $upstream -j ACCEPT
				[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				$fwCmd -t filter $t3 FORWARD -i $upstream -o $downstream -m state --state ESTABLISHED,RELATED -j ACCEPT
				[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1

				if [ "$mode" = "delete" ]; then
					$fwCmd -t nat $t ${upstream}_${downstream}_masq
					[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				fi
			;;

			*)
				echo "Unknown firewall command $cmd -- $arguments" >&2
				return 1
			;;
		esac

		# we save the command entered to the firewall repository file
		# this can be used to reapply the firewall and also clean the rules
		# from iptables.
		if [ "$singleRunMode" = "false" ]; then
			case $mode in
				create)
					# we add commands to the firewall instructions file
					cmdCtl "$fwFile" add "firewall $rootDir $fwType $cmd $arguments"
				;;

				delete)
					# we remove commands from the firewall instructions file
					cmdCtl "$fwFile" remove "firewall $rootDir $fwType $cmd $arguments"
				;;
			esac
		fi # not singleRunMode

		return 0
	fi
}

# firewall inside the jail itself
internalFirewall() { local rootDir=$1; shift; firewall $rootDir "internal" $@ ; }
# firewall on the base system
externalFirewall() { local rootDir=$1; shift; firewall $rootDir "external" $@ ; }

# checks if the firewall is correct.
# returns 0 when everything is ok and 1 if there is either an error or there is a rule missing
checkFirewall() {
	rootDir=$1
	local oldIFS="$IFS"
	IFS="
	"
	for cmd in $(cmdCtl "$rootDir/$firewallInstr" list); do
		remCmd=$(printf "%s" "$cmd" | $bb sed -e 's@firewall \(.*\) \(in\|ex\)ternal \(.*\)$@firewall \1 \2ternal -c \3@')

		IFS="$oldIFS" # we set back IFS for remCmd
		eval $remCmd
		[ "$?" != "0" ] && return 1

		oldIFS="$IFS"
		IFS="
		"
	done
	IFS="$oldIFS"

	return 0
}

# reapply firewall rules
resetFirewall() {
	rootDir=$1

	if [ "$privileged" = "0" ]; then
		echo "This function requires superuser privileges" >&2
		return
	fi

	local oldIFS="$IFS"
	IFS="
	"
	for cmd in $(cmdCtl "$rootDir/$firewallInstr" list); do
		remCmd=$(printf "%s" "$cmd" | $bb sed -e 's@firewall \(.*\) \(in\|ex\)ternal \(.*\)$@firewall \1 \2ternal -s \3@')

		IFS="$oldIFS" # we set back IFS for remCmd
		eval $remCmd
		[ "$?" != "0" ] && return 1

		oldIFS="$IFS"
		IFS="
		"
	done
	IFS="$oldIFS"
}

prepareChroot() {
	local rootDir=$1
	local unshareArgs=""
	local chrootArgs=""
	local chrootCmd="sh -c 'while :; do sleep 9999; done'"
	local preUnshare=""

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
		if [ "$privileged" = "1" ] || ([ "$privileged" = "0" ] && [ "$disableUnprivilegedNetworkNamespace" = "false" ]); then
			unshareArgs="$unshareArgs -n"
		fi
	fi

	devMounts=$(mountMany $rootDir/root -e "rw,noexec" $devMountPoints)
	roMounts=$(mountMany $rootDir/root -e "ro,exec" $roMountPoints)
	rwMounts=$(mountMany $rootDir/root -e "defaults" $rwMountPoints)

tasksBeforePivot=$($bb cat << EOF
$bb mount -tproc none $rootDir/root/proc
$bb mount -t tmpfs -o size=256k,mode=775 tmpfs $rootDir/root/dev
($bb sh -c ". $rootDir/jailLib.sh; addDevices $rootDir $availableDevices")
$devMounts
$roMounts
$rwMounts

if [ "$mountSys" = "true" ]; then
	if [ "$privileged" = "0" ] && [ "$disableUnprivilegedNetworkNamespace" = "true" ]; then
		echo "Could not mount the /sys directory. As an unprivileged user, the only way this is possible is by disabling the : UnprivilegedNetworkNamespace. Or you can always run this jail as a privileged user." >&2
	else
		$bb mount -tsysfs none $rootDir/root/sys
	fi
fi

EOF
)

	($preUnshare $bb unshare $unshareArgs ${unshareSupport}f -- $bb setpriv --bounding-set $corePrivileges $bb sh -c "$bb mount --make-private --bind $rootDir/root $rootDir/root; $tasksBeforePivot; cd $rootDir/root; $bb pivot_root . $rootDir/root/root; exec $nsBB chroot . sh -c \"$nsBB umount -l /root; $nsBB setpriv --bounding-set $chrootPrivileges $baseEnv $chrootCmd\"") &
	innerNSpid=$!
	$bb sleep 1
	innerNSpid=$($bb pgrep -P $innerNSpid)

	if [ "$innerNSpid" = "" ]; then
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

	execRemNS $nsPid $nsBB sh -c "exec $nsBB unshare -U --map-user=$userUID --map-group=$userGID $baseEnv $curArgs"
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
			chrootCmd=$(printf "%s" "$chrootCmd" | $nsBB sed -e 's/\x27/"/g') # replace all ' with "
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
		kill -9 $innerNSpid >/dev/null 2>/dev/null
		if [ "$?" = "0" ]; then
			$bb rm -f $rootDir/run/ns.pid
			$bb rm -f $rootDir/run/jail.pid
		fi
	fi
}

execNS() { execRemNS $innerNSpid "$@"; }

execRemNS() {
	local nsPid=$1
	shift
	#echo "NS [$nsPid] -- args : $nsenterSupport exec : \"$@\"" >&2
	$bb nsenter --preserve-credentials $nsenterSupport -t $nsPid -- "$@"
}
