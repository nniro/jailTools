# this is imported from newJail.sh
cat > $newChrootHolder/startRoot.sh << EOF
#! $sh
# Don't change anything in this script! Use rootCustomConfig.sh for your changes!

_JAILTOOLS_RUNNING=1

if [ "\$(id -u)" != "0" ]; then
	echo "This script has to be run with root permissions as it calls the command chroot"
	exit 1
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

parseArgs() {
	OPTIND=0
	local silentMode="false"
	while getopts s f 2>/dev/null; do
		case \$f in
			s) local silentMode="true";;
		esac
	done
	[ \$((\$OPTIND > 1)) = 1 ] && shift \$(expr \$OPTIND - 1)
	local title=\$1
	local validArguments="\$(printf "%s" "\$2" | sed -e "s/\('[^']*'\) /\1\n/g" | sed -e "/^'/ b; s/ /\n/g" | sed -e "s/'//g")"
	shift 2

	local oldIFS=\$IFS
	IFS="
	"
	for elem in \$(printf "%s" "\$validArguments"); do
		if [ "\$1" = "" ]; then
			[ "\$silentMode" = "false" ] && echo "\$title : Missing the required argument '\$elem'" >/dev/stderr
			IFS=\$oldIFS
			return 1
		fi
		shift
	done
	IFS=\$oldIFS
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
	local rootDir=\$1
	local mountOps=\$2
	shift 2

	for mount in \$(echo \$@); do
		if [ ! -d "\$rootDir/\$mount" ]; then
			echo \$rootDir/\$mount does not exist, creating it
			cmkdir -m 755 \$rootDir/\$mount
		fi
		$mountpointPath \$rootDir/\$mount >/dev/null 2>/dev/null || $mountPath -o \$mountOps --bind \$mount \$rootDir/\$mount
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
	if [ "\$jailNet" = "true" ]; then
		local rootDir=\$1
		local fwType=\$2
		shift 2
		local deleteMode="false"
		local singleRunMode="false" # it means this command should not be accounted in the firewall instructions file
		OPTIND=0
		while getopts ds f 2>/dev/null ; do
			case \$f in
				d) local deleteMode="true";;
				s) local singleRunMode="true";;
			esac
		done
		[ \$((\$OPTIND > 1)) = 1 ] && shift \$(expr \$OPTIND - 1)
		local cmd=\$1
		case "\$fwType" in
			"internal")
				local fwCmd="$ipPath netns exec \$netnsId $iptablesPath"
			;;

			"external")
				local fwCmd="$iptablesPath"
			;;

			*)
				echo "Don't call this function directly, use 'externalFirewall' or 'internalFirewall' instead." >/dev/stderr
				return
			;;
		esac
		shift
		local arguments="\$@"
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

			"snat")
				parseArgs "snat" "'the interface connected to the outbound network' 'the interface from which the packets originate'" \$arguments || return 1
				local upstream=\$1 # the snat goes through here
				local downstream=\$2 # this is the device to snat

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
				if [ "\$snatEth" != "" ]; then
					echo "\$firewallZoneName \$firewallNetZone ACCEPT" > \$firewallPath/policy.d/\$shortJailName.policy
					echo "MASQUERADE \$vethExt \$snatEth" > \$firewallPath/snat.d/\$shortJailName.snat
				fi
				echo "" > \$firewallPath/rules.d/\$shortJailName.rules
			;;

			"iptables")
				baseAddr=\$(echo \$ipInt | sed -e 's/\.[0-9]*$/\.0/') # convert 192.168.xxx.xxx to 192.168.xxx.0

				if [ "\$snatEth" != "" ]; then
					# this is to SNAT vethExt through snatEth
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
		[ "\$firewallType" = "shorewall" ] && [ "\$configNet" = "true" ] && shorewall restart >/dev/null 2>/dev/null
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

	prepCustom \$rootDir || return 1

	[ "\$firewallType" = "shorewall" ] && [ "\$configNet" = "true" ] && shorewall restart >/dev/null 2>/dev/null
	return 0
}

runChroot() {
	local chrootArgs="--userspec=$uid:$gid"
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

	printf "%s" "$chrootPath \$chrootArgs \$rootDir/root env - PATH=/usr/bin:/bin USER=\$user HOME=/home UID=$uid HOSTNAME=nowhere.here TERM=linux \$chrootCmd"
}

runJail() {
	local runChrootArgs=""
	local daemonize=false
	local enableUserNS="false"
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
			chrootCmd="\${chrootCmd}; sh -c 'while :; do sleep 9999; done'"
		fi
	fi

	if [ "\$userNS" = "true" ] && [ "\$enableUserNS" = "true" ]; then
		\$preUnshare $unsharePath ${unshareSupport}f -- $sh -c "$mountPath -tproc none \$rootDir/root/proc; su -c \"$unsharePath -Ur -- \$(runChroot \$runChrootArgs \$rootDir \$chrootCmd)\" - $USER"
	else
		\$preUnshare $unsharePath ${unshareSupport}f -- $sh -c "$mountPath -tproc none \$rootDir/root/proc; \$(runChroot \$runChrootArgs \$rootDir \$chrootCmd)"
	fi
}

stopChroot() {
	local rootDir=\$1

	stopCustom \$rootDir

	for mount in \$(echo \$devMountPoints \$roMountPoints \$rwMountPoints \$devMountPoints_CUSTOM \$roMountPoints_CUSTOM \$rwMountPoints_CUSTOM); do
                $mountpointPath \$rootDir/root/\$mount >/dev/null 2>/dev/null && $umountPath \$rootDir/root/\$mount
	done
	$mountpointPath \$rootDir/root >/dev/null 2>/dev/null && $umountPath \$rootDir/root

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

		if [ "\$configNet" = "true" ]; then
			shortJailName=\$(substring 0 13 \$jailName)
			case "\$firewallType" in
				"shorewall")
					for fwSection in zones interfaces policy snat rules; do
						[ -e \$firewallPath/\$fwSection.d/\$shortJailName.\$fwSection ] && rm \$firewallPath/\$fwSection.d/\$shortJailName.\$fwSection
					done
					shorewall restart >/dev/null 2>/dev/null
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

	local oldIFS=\$IFS
	IFS="
	"
	# removing the firewall rules inserted into the instructions file
	for cmd in \$(cmdCtl "\$rootDir/\$firewallInstr" list); do
		remCmd=\$(printf "%s" "\$cmd" | sed -e 's@firewall \(.*\) \(in\|ex\)ternal \(.*\)\$@firewall \1 \2ternal -d \3@')

		IFS=\$oldIFS # we set back IFS for remCmd
		eval \$remCmd

		local oldIFS=\$IFS
		IFS="
		"
	done
	IFS=\$oldIFS

	if [ -e \$rootDir/run/jail.pid ]; then
		nsPid=\$(findNS \$rootDir)
		#echo "nsPid : \$nsPid"
		[ "\$nsPid" != "" ] && (kill -9 \$nsPid; rm \$rootDir/run/jail.pid) >/dev/null 2>/dev/null
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

	nsLvl=1
	while : ; do
		local raw="\$(grep "PPid:[^0-9]*\$curPid$" /proc/*/status 2>/dev/null | sed -e 's/^\([^:]*\):.*$/\1/')"
		if [ "\$raw" = "" ]; then
			#local curPid=""
			break
		else
			local curPid=\$(basename \$(dirname \$raw))
			if [ "\$nsLvl" = "2" ]; then
				break
			fi
			nsLvl=\$((\$nsLvl + 1))
		fi
	done

	printf "%s" "\$curPid"
	return 0
}

case \$1 in

	*)
		cmdParse \$1 \$ownPath
	;;
esac

EOF
