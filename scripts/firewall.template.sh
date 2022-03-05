# globals :
#	*jailNet
#	bb
#	nsBB

bb="$BB"
shower="$JT_SHOWER"
runner="$JT_RUNNER"

if [ "$bb" = "" ]; then
	bb=busybox
	nsBB=busybox
fi

isPrivileged() {
	test $($bb id -u) = "0"
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

	exists() { 
		printf "%s" "$2" | $bb grep "\(^\|;\)$1;" >/dev/null 2>/dev/null
	}
	remove() { 
		exists "$1" "$2" && (printf "%s" "$2" | $bb sed -e "s@\(^\|;\)$1;@\1@") || printf "%s" "$2"
	}
	add() { 
		exists "$1" "$2" && printf "%s" "$2" || printf "%s%s;" "$2" "$1"
	}
	list() { 
		printf "%s" "$1" | $bb sed -e 's@;@\n@g'
	}

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

# don't use this function directly, use either internalFirewall or externalFirewall
# Internal is the firewall inside the jail
# External is the host system's firewall
firewall() {
	if ! isPrivileged; then
		echo "This function requires to be run with root privileges." >&2
		return 1
	fi
	if [ "$bb" = "" ]; then
		echo "Unable to find busybox" >&2
		return 1
	fi
	# this could be checked elsewhere
	#if [ "$jailNet" != "true" ]; then
	#	return
	#fi

	iptablesBin=$(PATH="$PATH:/sbin:/usr/sbin:/usr/local/sbin" $bb sh -c "command $bb which iptables" 2>/dev/null)
	if [ "$iptablesBin" = "" ]; then
		echo "unable to find a usable iptables executable" >&2
		return 1
	fi
	local fwInstrFile=$1
	local fwType=$2
	shift 2

	local singleRunMode="false" # it means this command should not be accounted in the firewall instructions file
	local mode="create"
	local arguments=''
	local fwCmd=''
	local cmd=''
	local upstream=''
	local downstream=''

	OPTIND=0
	while getopts dsc f 2>/dev/null ; do
		case $f in
			d) mode="delete";;
			s) singleRunMode="true";;
			c) mode="check";;
		esac
	done
	[ $(($OPTIND > 1)) = 1 ] && shift $($bb expr $OPTIND - 1)
	if [ "$1" != "" ]; then
		cmd=$1
		shift
	else
		# show some help message
		echo "please provide a command" >&2
		return 1
	fi
	case "$fwType" in
		"internal")
			fwCmd="execNS $nsBB $iptablesBin"
		;;

		"external")
			fwCmd="$iptablesBin"
		;;

		*)
			echo "Don't call this function directly, use 'externalFirewall' or 'internalFirewall' instead." >&2
			return 1
		;;
	esac
	#shift
	arguments="$@"
	[ ! -e $fwInstrFile ] && ($bb touch $fwInstrFile; $bb chmod o+r $fwInstrFile)

	case $mode in
		create)
			if [ "$singleRunMode" = "false" ]; then
				cmdCtl "$fwInstrFile" exists "firewall $fwInstrFile $fwType $cmd $arguments" && return 0
			fi # not singleRunMode
		;;

		delete)
			if [ "$singleRunMode" = "false" ]; then
				cmdCtl "$fwInstrFile" exists "firewall $fwInstrFile $fwType $cmd $arguments" || return 0
			fi # not singleRunMode
		;;
	esac

	case "$cmd" in
		"blockAll")
			parseArgs "blockAll" "'interface from' 'interface to'" $arguments || return 1
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
			$fwCmd $t INPUT -i $1 -p tcp -m tcp --dport 1:65535 -m state \! --state ESTABLISHED,RELATED -j REJECT
			[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
			$fwCmd $t INPUT -i $1 -p udp -m udp --dport 1:65535 -m state \! --state ESTABLISHED,RELATED -j REJECT
			[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
			# block all outgoing packets except established ones
			$fwCmd $t OUTPUT -o $2 -p all -m state \! --state ESTABLISHED,RELATED -j REJECT
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
					firewall $fwInstrFile $fwType -s "openPort" $1 $2 "tcp" $3
					[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				;;

				delete)
					firewall $fwInstrFile $fwType -d -s "openPort" $1 $2 "tcp" $3
					[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				;;

				check)
					firewall $fwInstrFile $fwType -c -s "openPort" $1 $2 "tcp" $3
					[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				;;
			esac
		;;

		"openUdpPort")
			parseArgs "openUdpPort" "'interface' 'destination port'" $arguments || return 1
			parseArgs "openUdpPort" "'interface from' 'interface to' 'destination port'" $arguments || return 1
			case $mode in
				create)
					firewall $fwInstrFile $fwType -s "openPort" $1 $2 "udp" $3
					[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				;;

				delete)
					firewall $fwInstrFile $fwType -d -s "openPort" $1 $2 "udp" $3
					[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				;;

				check)
					firewall $fwInstrFile $fwType -c -s "openPort" $1 $2 "udp" $3
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
					firewall $fwInstrFile $fwType -s "allowConnection" tcp $1 $2 $3
					[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				;;

				delete)
					firewall $fwInstrFile $fwType -d -s "allowConnection" tcp $1 $2 $3
					[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				;;

				check)
					firewall $fwInstrFile $fwType -c -s "allowConnection" tcp $1 $2 $3
					[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				;;
			esac
		;;

		"allowUdpConnection")
			parseArgs "allowUdpConnection" "'output interface' 'destination address' 'destination port'" $arguments || return 1
			case $mode in
				create)
					firewall $fwInstrFile $fwType -s "allowConnection" udp $1 $2 $3
					[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				;;

				delete)
					firewall $fwInstrFile $fwType -d -s "allowConnection" udp $1 $2 $3
					[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				;;

				check)
					firewall $fwInstrFile $fwType -c -s "allowConnection" udp $1 $2 $3
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
					firewall $fwInstrFile $fwType -s "dnat" tcp $1 $2 $3 $4 $5
					[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				;;

				delete)
					firewall $fwInstrFile $fwType -d -s "dnat" tcp $1 $2 $3 $4 $5
					[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				;;

				check)
					firewall $fwInstrFile $fwType -c -s "dnat" tcp $1 $2 $3 $4 $5
					[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				;;
			esac
		;;

		"dnatUdp")
			parseArgs "dnatUdp" "'input interface' 'output interface' 'source port' 'destination address' 'destination port'" $arguments || return 1
			case $mode in
				create)
					firewall $fwInstrFile $fwType -s "dnat" udp $1 $2 $3 $4 $5
					[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				;;

				delete)
					firewall $fwInstrFile $fwType -d -s "dnat" udp $1 $2 $3 $4 $5
					[ "$?" != "0" ] && [ "$mode" = "check" ] && return 1
				;;

				check)
					firewall $fwInstrFile $fwType -c -s "dnat" udp $1 $2 $3 $4 $5
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
				cmdCtl "$fwInstrFile" add "firewall $fwInstrFile $fwType $cmd $arguments"
			;;

			delete)
				# we remove commands from the firewall instructions file
				cmdCtl "$fwInstrFile" remove "firewall $fwInstrFile $fwType $cmd $arguments"
			;;
		esac
	fi # not singleRunMode

	return 0
}

# firewall inside the jail itself
#internalFirewall() { local fwInstrFile=$1; shift; firewall $rootDir "internal" $@ ; }
# firewall on the base system
#externalFirewall() { local fwInstrFile=$1; shift; firewall $rootDir "external" $@ ; }

# checks if the firewall is correct.
# returns 0 when everything is ok and 1 if there is either an error or there is a rule missing
checkFirewall() {
	firewallInstr=$1
	local oldIFS="$IFS"
	IFS="
	"
	for cmd in $(cmdCtl "$firewallInstr" list); do
		remCmd=$(printf "%s" "$cmd" | $bb sed -e 's@firewall \(.*\) \(in\|ex\)ternal \(.*\)$@firewall \1 \2ternal -c \3@')

		IFS="$oldIFS" # we set back IFS for remCmd
		eval $remCmd >/dev/null 2>/dev/null
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
	firewallInstr=$1

	if ! isPrivileged; then
		echo "This function requires superuser privileges" >&2
		return
	fi

	local oldIFS="$IFS"
	IFS="
	"
	for cmd in $(cmdCtl "$firewallInstr" list); do
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

# firewall Command Line Interface
firewallCLI() {
	if [ "$1" = "" ]; then

		instrFile=/tmp/firewallInstructions.txt
	else
		instrFile=$1
		shift
	fi

	help() {
 	       echo "Valid commands : firewall | check | reset"
	}

	cmd=$1
	shift
	case $cmd in
		help)
	                help
	        ;;

	        firewall)
	                firewall $instrFile external $@
	        ;;

	        check)
	                checkFirewall $instrFile >/dev/null 2>/dev/null && echo "All is fine" || echo "Error detected"
	        ;;

		reset)
			resetFirewall $instrFile
		;;

		*)
			help
			exit 1
		;;
	esac
}
