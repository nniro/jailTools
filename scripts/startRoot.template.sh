# this is imported from newJail.sh
cat > $newChrootHolder/startRoot.sh << EOF
#! $sh
# Don't change anything in this script! Use rootCustomConfig.sh for your changes!

_JAILTOOLS_RUNNING=1

canMount=1
privileged=0
if [ "\$(id -u)" != "0" ]; then
	echo "You are running this script unprivileged, most features will not work"
	canMount=0
else
	privileged=1
fi

ownPath=\$(dirname \$0)
firewallInstr="run/firewall.instructions"

# substring offset <optional length> string
# cuts a string at the starting offset and wanted length.
substring() {
        local init=\$1; shift
        if [ "\$2" != "" ]; then toFetch="\(.\{\$1\}\).*"; shift; else local toFetch="\(.*\)"; fi
        echo "\$1" | sed -e "s/^.\{\$init\}\$toFetch$/\1/"
}

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

userNS=$userNS
netNS=$netNS
hasIptables=$hasIptables

firewallType=iptables

iptablesBin=$iptablesPath

innerMountCommands=""

if [ "\$privileged" = "0" ]; then
	if [ "\$userNS" != "true" ]; then
		echo "The user namespace is not supported. Can't start an unprivileged jail without it, bailing out."
		exit 1
	fi

	if [ "\$jailNet" = "true" ]; then
		echo "jailNet is disabled"
		jailNet=false
	fi

	if [ "\$createBridge" = "true" ]; then
		echo "createBridge is disabled"
		createBridge=false
	fi
fi

if [ "\$netNS" = "false" ] && [ "\$jailNet" = "true" ]; then
	jailNet=false
	echo "jailNet is set to false automatically as it needs network namespace support which is not available."
fi

if [ "\$configNet" = "true" ]; then
	# final attempt to find iptables
	if [ "\$hasIptables" = "false" ]; then
		iptablesBin=\$(PATH="\$PATH:/sbin:/usr/sbin:/usr/local/sbin" command which iptables 2>/dev/null)

		if [ "\$iptablesBin" = "" ]; then
			hasIptables=false
			iptablesPath=iptables
		else
			hasIptables=true
		fi
	fi

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
@EOF
)

# read-write mount points with exec
rwMountPoints=\$(cat << EOF
@EOF
)

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
		case \$f in
			m) callArgs="\$callArgs --mode=\$OPTARG";;
			e) isOutput="true";;
		esac
	done
	[ \$((\$OPTIND > 1)) = 1 ] && shift \$(expr \$OPTIND - 1)
	arguments="\$@"

        for dir in \$(echo \$arguments); do
                local subdirs="\$(echo \$dir | sed -e 's/\//\n/g')"
		if [ "\$(substring 0 1 \$dir)" = "/" ]; then # checking for an absolute path
			local parentdir="/"
		else # relative path
	                local parentdir=""
		fi
                for subdir in \$(echo \$subdirs); do
			if [ "\$isOutput" = "false" ]; then
				if [ ! -d \$parentdir\$subdir ]; then
					mkdir \$callArgs \$parentdir\$subdir
				fi
			else
				result="\$result mkdir -p \$callArgs \$parentdir\$subdir;"
			fi

			if [ "\$parentdir" = "" ]; then
				local parentdir="\$subdir/"
			else
				local parentdir="\$parentdir\$subdir/"
			fi
                done
        done

	if [ "\$isOutput" = "true" ]; then
		echo \$result
	fi
}

getDeviceInfo() {
	rootDir=\$1
	shift
	# TODO this could be implemented with stat -c "%F %t %T"  just that the '%F' gives something like "character special file"
	printf "%c %d %d\n" \$(\$rootDir/root/bin/busybox stat \$1 | grep "\(special file\|Device type\)" | sed -ne 's/.* \(.\)[^ ]* special file$/\1/ p; N; s/.* Device type: \([^,]*\),\(.*\)$/ 0x\1 0x\2/ p' | sed -ne 'N; s/\n// p')
}

addDevices() {
	local rootDir=\$1
	shift
	local i=""
	local bb="\$rootDir/root/bin/busybox"

	if [ "\$privileged" = "0" ]; then
		return
	fi
	while [ "\$1" != "" ]; do
		i="/dev/\$1"
		if [ ! -b \$i ] && [ ! -c \$i ]; then
			echo "invalid device \\\`\$i'"
			return 1
		else
			innerMountCommands="\$innerMountCommands if [ \"\$(dirname \$i)\" != \"/dev\" ]; then \$(cmkdir -e -m 755 \$rootDir/root/\$(dirname \$i)) fi;"

			innerMountCommands="\$innerMountCommands mknod \$rootDir/root\$i \$(getDeviceInfo \$rootDir \$i);"
			innerMountCommands="\$innerMountCommands chmod \$(\$bb stat -c %a \$i) \$rootDir/root\$i;"
			innerMountCommands="\$innerMountCommands chgrp \$(cat \$rootDir/root/etc/group | grep "\${user}:" | sed -e 's/.*:\([0-9]*\):$/\1/') \$rootDir/root\$i;"
		fi
		shift
	done

	return 0
}

parseArgs() {
	OPTIND=0
	local silentMode="false"
	local oldIFS=''
	while getopts s f 2>/dev/null; do
		case \$f in
			s) local silentMode="true";;
		esac
	done
	[ \$((\$OPTIND > 1)) = 1 ] && shift \$(expr \$OPTIND - 1)
	local title="\$1"
	local validArguments="\$(printf "%s" "\$2" | sed -e "s/\('[^']*'\) /\1\n/g" | sed -e "/^'/ b; s/ /\n/g" | sed -e "s/'//g")"
	shift 2

	oldIFS="\$IFS"
	IFS="
	"
	for elem in \$(printf "%s" "\$validArguments"); do
		if [ "\$1" = "" ]; then
			[ "\$silentMode" = "false" ] && echo "\$title : Missing the required argument '\$elem'" >/dev/stderr
			IFS="\$oldIFS"
			return 1
		fi
		shift
	done
	IFS="\$oldIFS"
	return 0
}

# This function is meant to interface with an instructions file.
# the instructions file contains data separated by semicolons, each are called command.
# we can check if a command is present, remove and add them. We can also output a version
# that is fitting to be looped.
cmdCtl() {
	local file=\$1
	local cmd=\$2
	shift 2
	local result=""

	exists() { printf "%s" "\$2" | grep "\(^\|;\)\$1;" >/dev/null 2>/dev/null;}
	remove() { exists "\$1" "\$2" && (printf "%s" "\$2" | sed -e "s@\(^\|;\)\$1;@\1@") || printf "%s" "\$2";}
	add() { exists "\$1" "\$2" && printf "%s" "\$2" || printf "%s%s;" "\$2" "\$1";}
	list() { printf "%s" "\$1" | sed -e 's@;@\n@g';}


	if [ ! -e \$file ]; then
		if [ ! -d \$(dirname \$file) ]; then
			mkdir -p \$(dirname \$file)
		fi
		touch \$file
	fi

	case \$cmd in
		exists) exists "\$1" "\$(cat \$file)" ;;
		remove) remove "\$1" "\$(cat \$file)" > \$file ;;
		add) add "\$1" "\$(cat \$file)" > \$file ;;
		list) list "\$(cat \$file)" ;;
		*)
			echo "Invalid command entered"
			return 1
		;;
	esac
}

mountMany() {
	OPTIND=0
	local rootDir=\$1
	shift
	local isOutput="false"
	local result=""
	while getopts e f 2>/dev/null; do
		case \$f in
			e) isOutput="true";;
		esac
	done
	[ \$((\$OPTIND > 1)) = 1 ] && shift \$(expr \$OPTIND - 1)
	local mountOps=\$1
	shift

	# this only works with a privileged user
	if [ "\$privileged" = "0" ]; then
		return
	fi

	for mount in \$(echo \$@); do
		if [ "\$isOutput" = "false" ]; then
			if [ ! -d "\$rootDir/\$mount" ]; then
				echo \$rootDir/\$mount does not exist, creating it
				cmkdir -m 755 \$rootDir/\$mount
			fi
			$mountpointPath \$rootDir/\$mount >/dev/null 2>/dev/null || $mountPath -o \$mountOps --bind \$mount \$rootDir/\$mount
		else # isOutput = true
			result="\$result if [ ! -d \"\$rootDir/\$mount\" ]; then \$(cmkdir -e -m 755 \$rootDir/\$mount) fi;"
			result="\$result $mountpointPath \$rootDir/\$mount >/dev/null 2>/dev/null || $mountPath -o \$mountOps --bind \$mount \$rootDir/\$mount;"
		fi
	done

	if [ "\$isOutput" = "true" ]; then
		echo \$result
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
                        echo "joinBridgeByJail: This jail does not have a bridge, aborting joining."
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

# don't use this function directly, use either internalFirewall or externalFirewall
# Internal is for the jail itself
# External is the host system's firewall
firewall() {
	if [ "\$privileged" = "0" ]; then
		return
	fi
	local rootDir=''
	local fwType=''
	local deleteMode="false"
	local singleRunMode="false" # it means this command should not be accounted in the firewall instructions file
	local arguments=''
	local fwCmd=''
	local cmd=''
	local upstream=''
	local downstream=''
	if [ "\$jailNet" = "true" ]; then
		rootDir=\$1
		fwType=\$2
		shift 2
		OPTIND=0
		while getopts ds f 2>/dev/null ; do
			case \$f in
				d) deleteMode="true";;
				s) singleRunMode="true";;
			esac
		done
		[ \$((\$OPTIND > 1)) = 1 ] && shift \$(expr \$OPTIND - 1)
		cmd=\$1
		case "\$fwType" in
			"internal")
				fwCmd="$ipPath netns exec \$netnsId \$iptablesBin"
			;;

			"external")
				fwCmd="\$iptablesBin"
			;;

			*)
				echo "Don't call this function directly, use 'externalFirewall' or 'internalFirewall' instead." >/dev/stderr
				return
			;;
		esac
		shift
		arguments="\$@"
		fwFile="\$rootDir/\$firewallInstr"
		[ ! -e \$fwFile ] && (touch \$fwFile; chmod o+r \$fwFile)

		if [ "\$deleteMode" = "false" ]; then
			cmdCtl "\$fwFile" exists "firewall \$rootDir \$fwType \$cmd \$arguments" && return 0
		else # deleteMode
			if [ "\$singleRunMode" = "false" ]; then
				cmdCtl "\$fwFile" exists "firewall \$rootDir \$fwType \$cmd \$arguments" || return 0
			fi # not singleRunMode
		fi # deleteMode

		case "\$cmd" in
			"blockAll")
				parseArgs "blockAll" "" \$arguments || return 1
				if [ "\$deleteMode" = "false" ]; then
					# block all tcp packets except those that are established
					# and related (this is appended at the bottom)
					\$fwCmd -A INPUT -p tcp -m tcp --dport 1:65535 -m state \! --state ESTABLISHED,RELATED -j REJECT
					\$fwCmd -A INPUT -p udp -m udp --dport 1:65535 -m state \! --state ESTABLISHED,RELATED -j REJECT
					# block all outgoing packets except established ones
					\$fwCmd -A OUTPUT -p all -m state \! --state ESTABLISHED,RELATED -j REJECT
				else # deleteMode
					\$fwCmd -D INPUT -p tcp -m tcp --dport 1:65535 -m state \! --state ESTABLISHED,RELATED -j REJECT
					\$fwCmd -D INPUT -p udp -m udp --dport 1:65535 -m state \! --state ESTABLISHED,RELATED -j REJECT
					\$fwCmd -D OUTPUT -p all -m state \! --state ESTABLISHED,RELATED -j REJECT
				fi # deleteMode
			;;

			"openPort")
				parseArgs "openPort" "'interface from' 'interface to' 'tcp or udp' 'destination port'" \$arguments || return 1
				if [ "\$deleteMode" = "false" ]; then
					# "inserted" so they are before the reject rules

					# request ext -> int:port
					\$fwCmd -I OUTPUT -o \$1 -p \$3 --dport \$4 -j ACCEPT
					\$fwCmd -I OUTPUT -o \$2 -p \$3 --sport \$4 -j ACCEPT
					\$fwCmd -I INPUT -i \$2 -p \$3 --dport \$4 -j ACCEPT
					# response int:port -> ext
					\$fwCmd -I INPUT -i \$1 -p \$3 --sport \$4 -j ACCEPT
				else # deleteMode

					\$fwCmd -D OUTPUT -o \$1 -p \$3 --dport \$4 -j ACCEPT
					\$fwCmd -D OUTPUT -o \$2 -p \$3 --sport \$4 -j ACCEPT
					\$fwCmd -D INPUT -i \$2 -p \$3 --dport \$4 -j ACCEPT
					\$fwCmd -D INPUT -i \$1 -p \$3 --sport \$4 -j ACCEPT
				fi # deleteMode
			;;

			"openTcpPort")
				parseArgs "openTcpPort" "'interface from' 'interface to' 'destination port'" \$arguments || return 1
				if [ "\$deleteMode" = "false" ]; then
					firewall \$rootDir \$fwType -s "openPort" \$1 \$2 "tcp" \$3
				else # deleteMode
					firewall \$rootDir \$fwType -d -s "openPort" \$1 \$2 "tcp" \$3
				fi # deleteMode
			;;

			"openUdpPort")
				parseArgs "openUdpPort" "'interface' 'destination port'" \$arguments || return 1
				parseArgs "openUdpPort" "'interface from' 'interface to' 'destination port'" \$arguments || return 1
				if [ "\$deleteMode" = "false" ]; then
					firewall \$rootDir \$fwType -s "openPort" \$1 \$2 "udp" \$3
				else # deleteMode
					firewall \$rootDir \$fwType -d -s "openPort" \$1 \$2 "udp" \$3
				fi # deleteMode
			;;

			"allowConnection")
				parseArgs "allowConnection" "'tcp or udp' 'output interface' 'destination address' 'destination port'" \$arguments || return 1
				if [ "\$deleteMode" = "false" ]; then
					\$fwCmd -I OUTPUT -p \$1 -o \$2 -d \$3 --dport \$4 -j ACCEPT
				else # deleteMode
					\$fwCmd -D OUTPUT -p \$1 -o \$2 -d \$3 --dport \$4 -j ACCEPT
				fi # deleteMode
			;;

			"allowTcpConnection")
				parseArgs "allowTcpConnection" "'output interface' 'destination address' 'destination port'" \$arguments || return 1
				if [ "\$deleteMode" = "false" ]; then
					firewall \$rootDir \$fwType -s "allowConnection" tcp \$1 \$2 \$3
				else # deleteMode
					firewall \$rootDir \$fwType -d -s "allowConnection" tcp \$1 \$2 \$3
				fi # deleteMode
			;;

			"allowUdpConnection")
				parseArgs "allowUdpConnection" "'output interface' 'destination address' 'destination port'" \$arguments || return 1
				if [ "\$deleteMode" = "false" ]; then
					firewall \$rootDir \$fwType -s "allowConnection" udp \$1 \$2 \$3
				else # deleteMode
					firewall \$rootDir \$fwType -d -s "allowConnection" udp \$1 \$2 \$3
				fi # deleteMode
			;;

			"dnat")
				parseArgs "dnat" "'tcp or udp' 'input interface' 'output interface' 'source port' 'destination address' 'destination port'" \$arguments || return 1
				if [ "\$deleteMode" = "false" ]; then
					\$fwCmd -t nat -A PREROUTING -i \$2 -p \$1 -m \$1 --dport \$4 -j DNAT --to-destination \$5:\$6
					\$fwCmd -t filter -I FORWARD -p \$1 -i \$2 -o \$3 -m state --state NEW,ESTABLISHED,RELATED -m \$1 --dport \$6 -j ACCEPT
					\$fwCmd -t filter -I FORWARD -p \$1 -i \$3 -o \$2 -m state --state ESTABLISHED,RELATED -j ACCEPT
				else # deleteMode
					\$fwCmd -t nat -D PREROUTING -i \$2 -p \$1 -m \$1 --dport \$4 -j DNAT --to-destination \$5:\$6
					\$fwCmd -t filter -D FORWARD -p \$1 -i \$2 -o \$3 -m state --state NEW,ESTABLISHED,RELATED -m \$1 --dport \$6 -j ACCEPT
					\$fwCmd -t filter -D FORWARD -p \$1 -i \$3 -o \$2 -m state --state ESTABLISHED,RELATED -j ACCEPT
				fi # deleteMode
			;;

			"dnatTcp")
				parseArgs "dnatTcp" "'input interface' 'output interface' 'source port' 'destination address' 'destination port'" \$arguments || return 1
				if [ "\$deleteMode" = "false" ]; then
					firewall \$rootDir \$fwType -s "dnat" tcp \$1 \$2 \$3 \$4 \$5
				else # deleteMode
					firewall \$rootDir \$fwType -d -s "dnat" tcp \$1 \$2 \$3 \$4 \$5
				fi # deleteMode			
			;;

			"dnatUdp")
				parseArgs "dnatUdp" "'input interface' 'output interface' 'source port' 'destination address' 'destination port'" \$arguments || return 1
				if [ "\$deleteMode" = "false" ]; then
					firewall \$rootDir \$fwType -s "dnat" udp \$1 \$2 \$3 \$4 \$5
				else # deleteMode
					firewall \$rootDir \$fwType -d -s "dnat" udp \$1 \$2 \$3 \$4 \$5
				fi # deleteMode			
			;;

			"snat")
				parseArgs "snat" "'the interface connected to the outbound network' 'the interface from which the packets originate'" \$arguments || return 1
				upstream=\$1 # the snat goes through here
				downstream=\$2 # this is the device to snat

				baseAddr=\$(echo \$ipInt | sed -e 's/\.[0-9]*$/\.0/') # convert 192.168.xxx.xxx to 192.168.xxx.0

				if [ "\$deleteMode" = "false" ]; then
					\$fwCmd -t nat -N \${upstream}_\${downstream}_masq
					\$fwCmd -t nat -A POSTROUTING -o \$upstream -j \${upstream}_\${downstream}_masq
					\$fwCmd -t nat -A \${upstream}_\${downstream}_masq -s \$baseAddr/\$ipIntBitmask -j MASQUERADE

					\$fwCmd -t filter -I FORWARD -i \$downstream -o \$upstream -j ACCEPT
					\$fwCmd -t filter -I FORWARD -i \$upstream -o \$downstream -m state --state ESTABLISHED,RELATED -j ACCEPT
				else # deleteMode
					\$fwCmd -t nat -D POSTROUTING -o \$upstream -j \${upstream}_\${downstream}_masq
					\$fwCmd -t nat -D \${upstream}_\${downstream}_masq -s \$baseAddr/\$ipIntBitmask -j MASQUERADE
					\$fwCmd -t filter -D FORWARD -i \$downstream -o \$upstream -j ACCEPT
					\$fwCmd -t filter -D FORWARD -i \$upstream -o \$downstream -m state --state ESTABLISHED,RELATED -j ACCEPT
					\$fwCmd -t nat -X \${upstream}_\${downstream}_masq
				fi # deleteMode
			;;

			*)
				echo "Unknown firewall command \$cmd -- \$arguments"
				return 1
			;;
		esac

		# we save the command entered to the firewall repository file
		# this can be used to reapply the firewall and also clean the rules
		# from iptables.
		if [ "\$singleRunMode" = "false" ]; then
			if [ "\$deleteMode" = "false" ]; then
				# we add commands to the firewall instructions file
				cmdCtl "\$fwFile" add "firewall \$rootDir \$fwType \$cmd \$arguments"
			else # deleteMode
				# we remove commands from the firewall instructions file
				cmdCtl "\$fwFile" remove "firewall \$rootDir \$fwType \$cmd \$arguments"
			fi # deleteMode
		fi # not singleRunMode

		return 0
	fi
}

# firewall inside the jail itself
internalFirewall() { local rootDir=\$1; shift; firewall \$rootDir "internal" \$@ ; }
# firewall on the base system
externalFirewall() { local rootDir=\$1; shift; firewall \$rootDir "external" \$@ ; }

prepareChroot() {
	local rootDir=\$1

	if ! \$($ipPath netns list | sed -ne "/^\$netnsId\($\| .*$\)/ q 1; $ q 0") || [ -e \$rootDir/run/jail.pid ]; then
		echo "This jail was already started, bailing out."
		return 1
	fi
	if [ "\$privileged" = "1" ]; then
		$mountPath --bind \$rootDir/root \$rootDir/root
	fi

	# dev
	innerMountCommands="\$innerMountCommands \$(mountMany \$rootDir/root -e "rw,noexec" \$devMountPoints)"
	mountMany \$rootDir/root "ro,exec" \$roMountPoints
	mountMany \$rootDir/root "defaults" \$rwMountPoints

	innerMountCommands="\$innerMountCommands \$(mountMany \$rootDir/root -e "rw,noexec" \$devMountPoints_CUSTOM)"
	mountMany \$rootDir/root "ro,exec" \$roMountPoints_CUSTOM
	mountMany \$rootDir/root "defaults" \$rwMountPoints_CUSTOM

	if [ "\$jailNet" = "true" ]; then
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

			if [ "\$setNetAccess" = "true" ] && [ "\$netInterface" != "" ]; then
				externalFirewall \$rootDir snat \$netInterface \$vethExt
			fi
		fi
	fi

	if [ "\$privileged" = "1" ]; then
		# this protects from an adversary to delete and recreate root owned files
		for i in bin root etc lib usr sbin sys . ; do chown root:root \$rootDir/root/\$i; chmod 755 \$rootDir/root/\$i; done
		for i in passwd shadow group; do chown root:root \$rootDir/root/etc/\$i; chmod 600 \$rootDir/root/etc/\$i; done
		for i in passwd group; do chmod 644 \$rootDir/root/etc/\$i; done
	fi

	prepCustom \$rootDir || return 1

	return 0
}

runChroot() {
	local chrootArgs="-u $uid:$gid"
	OPTIND=0
	while getopts r f 2>/dev/null ; do
		case \$f in
			r) local chrootArgs="";; # run as root
		esac
	done
	[ \$((\$OPTIND > 1)) = 1 ] && shift \$(expr \$OPTIND - 1)
	local rootDir=\$1
	shift

	if [ \$((\$# > 0)) = 0 ]; then
		local chrootCmd="/bin/sh"
	else
		local chrootCmd=""
                while [ "\$1" != "" ]; do
                        local chrootCmd="\$chrootCmd \$1"
                        shift
                done
	fi

	printf "%s" "$chrootPath \$chrootArgs -/ \$rootDir/root env - PATH=/usr/bin:/bin USER=\$user HOME=/home UID=$uid HOSTNAME=nowhere.here TERM=linux \$chrootCmd"
}

runJail() {
	local runChrootArgs=""
	local daemonize=false
	local enableUserNS="false"
	local jailMainMounts=""
	OPTIND=0
	while getopts rfd f 2>/dev/null ; do
		case \$f in
			r) local runChrootArgs="-r";; # run as root
			f) local enableUserNS="true";; # run as a fake root (with the user namespace)
			d) local daemonize=true;;
		esac
	done
	[ \$((\$OPTIND > 1)) = 1 ] && shift \$(expr \$OPTIND - 1)
	local rootDir=\$1
	shift
	local chrootCmd=""
	if [ \$((\$# > 0)) = 1 ]; then
		while [ "\$1" != "" ]; do
			local curArg=""
			if [ "\$(printf "%s" "\$1" | sed -ne '/ / ! a0' -e '/ / a1')" = "1" ]; then
				curArg="'\$1'"
			else
				curArg="\$1"
			fi
			local chrootCmd="\$chrootCmd \$curArg"
			shift
		done
	fi

	local preUnshare=""

	if [ "\$jailNet" = "true" ]; then
		local preUnshare="\$preUnshare $ipPath netns exec \$netnsId"
	fi

	echo \$$ > \$rootDir/run/jail.pid
	chmod o+r \$rootDir/run/jail.pid

	if [ "\$daemonize" = "true" ]; then
		if [ "\$chrootCmd" = "" ]; then
			chrootCmd="sh -c 'while :; do sleep 9999; done'"
		else
			chrootCmd=\$(printf "%s" "\$chrootCmd" | sed -e 's/\\x27/"/g') # replace all ' with "
			chrootCmd="sh -c '\${chrootCmd}; while :; do sleep 9999; done'"
		fi
	fi


	if [ "\$privileged" = "1" ]; then
		jailMainMounts="$mountPath -tproc none -o hidepid=2 \$rootDir/root/proc;" # this is for the /proc folder so commands like 'ps' work correctly
		jailMainMounts="\$jailMainMounts $mountPath -t tmpfs -o size=256k tmpfs \$rootDir/root/dev;" # this makes sure that the devices in /dev are removed when the jail closes

		if [ "\$userNS" = "true" ] && [ "\$enableUserNS" = "true" ]; then
			\$preUnshare $unsharePath ${unshareSupport}f -- $sh -c "\$jailMainMounts \$innerMountCommands su -c \"$unsharePath -Ur -- exec \$(runChroot \$runChrootArgs \$rootDir \$chrootCmd)\" - $USER"
		else
			\$preUnshare $unsharePath ${unshareSupport}f -- $sh -c "\$jailMainMounts \$innerMountCommands exec \$(runChroot \$runChrootArgs \$rootDir \$chrootCmd)"
		fi
	else # unprivileged
		if [ "\$setNetAccess" = "false" ] && [ "\$netNS" = "true" ]; then
			$unsharePath -Ur -- /usr/bin/unshare ${unshareSupport}nf -- $sh -c "exec \$(runChroot -r \$runChrootArgs \$rootDir \$chrootCmd)"
		else
			$unsharePath -Ur -- /usr/bin/unshare ${unshareSupport}f -- $sh -c "exec \$(runChroot -r \$runChrootArgs \$rootDir \$chrootCmd)"
		fi
	fi # unprivileged
	return \$?
}

stopChroot() {
	local rootDir=\$1

	stopCustom \$rootDir

	
	if [ "\$privileged" = "1" ]; then
		for mount in \$(echo \$devMountPoints \$roMountPoints \$rwMountPoints \$devMountPoints_CUSTOM \$roMountPoints_CUSTOM \$rwMountPoints_CUSTOM); do
			$mountpointPath \$rootDir/root/\$mount >/dev/null 2>/dev/null && $umountPath \$rootDir/root/\$mount
		done
		$mountpointPath \$rootDir/root >/dev/null 2>/dev/null && $umountPath \$rootDir/root
	fi

	if [ "\$?" != 0 ]; then
		echo "Unable to unmount certain directories, aborting."
		return 0
	fi

	if [ "\$jailNet" = "true" ]; then
		if \$($ipPath netns list | sed -ne "/\$netnsId/ q 1; $ q 0"); then
			echo "netnsId \\\`\$netnsId' does not exist, exiting..."
			exit 0
		fi
		if [ "\$createBridge" = "true" ]; then
			$ipPath netns exec \$netnsId $ipPath link set down \$bridgeName
			$ipPath netns exec \$netnsId $brctlPath delbr \$bridgeName
		fi

		$ipPath netns delete \$netnsId
	fi

	local oldIFS="\$IFS"
	IFS="
	"
	# removing the firewall rules inserted into the instructions file
	for cmd in \$(cmdCtl "\$rootDir/\$firewallInstr" list); do
		remCmd=\$(printf "%s" "\$cmd" | sed -e 's@firewall \(.*\) \(in\|ex\)ternal \(.*\)\$@firewall \1 \2ternal -d \3@')

		IFS="\$oldIFS" # we set back IFS for remCmd
		eval \$remCmd

		oldIFS="\$IFS"
		IFS="
		"
	done
	IFS="\$oldIFS"

	if [ -e \$rootDir/run/jail.pid ]; then
		nsPid=\$(findNS \$rootDir)
		#echo "nsPid : \$nsPid"
		[ "\$nsPid" != "" ] && (kill -9 \$nsPid; rm \$rootDir/run/jail.pid) >/dev/null 2>/dev/null
	fi

	if [ "\$privileged" = "1" ]; then
		for i in bin root etc lib usr sbin sys . ; do chown $uid:$gid \$rootDir/root/\$i; done
		for i in passwd shadow group; do chown $uid:$gid \$rootDir/root/etc/\$i; done
	fi
}

findNS() {
	rootDir=\$1

	local curPid="\$(cat \$rootDir/run/jail.pid)"

	if [ "\$curPid" = "" ]; then
		if ! \$($ipPath netns list | sed -ne "/^\$netnsId\($\| .*$\)/ q 1; $ q 0"); then
			# This jail is running
			return 2
		else
			# this jail is stopped
			return 1
		fi
	fi

	# first pgrep gets the unshare command and the second pgrep is to get the first child of that.
	$pgrepPath -P \$($pgrepPath -P \$curPid | sed -ne '$ p') | sed -ne '$ p'

	return 0
}

case \$1 in

	*)
		s1=\$1
		shift
		cmdParse \$s1 \$ownPath \$@
	;;
esac

EOF