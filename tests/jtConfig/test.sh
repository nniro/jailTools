#! /bin/sh

# this tests the jt config command.

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/jtConfig

$jtPath new $jail 2>&1 >/dev/null || exit 1

testGet() {
	OPTIND=0
	default=""
	reversed="false"
	checkPresentInConf="false"
	resultFilter=""
	while getopts drpf: f 2>/dev/null; do
		case $f in
			d) default="--default";;
			r) reversed="true";;
			p) checkPresentInConf="true";;
			f) resultFilter="$OPTARG";;
		esac
	done
	[ $(($OPTIND > 1)) = 1 ] && shift $(expr $OPTIND - 1)

	description=$1
	conf=$2
	expectedVal=$3

	result=$($jtPath config $default --get $conf)
	err=$?

	if [ "$resultFilter" != "" ]; then
		result=$(printf "%s" "$result" | sed $resultFilter)
	fi


	if [ "$err" != "0" ]; then
		[ "$reversed" = "true" ] && return 0
		echo "Test : $description -- failed"
		echo "An error was returned by the call"
		return 1
	fi

	if printf "%s" "$result" | grep -q "$expectedVal"; then
		if [ "$reversed" = "true" ]; then
			echo "Test : $description -- failed"
			echo "We expected to fail but instead succeded"
			return 1
		fi

		if [ "$checkPresentInConf" = "true" ]; then
			if [ "$default" = "--default" ]; then
				confFile="rootDefaultConfig.sh"
			else
				confFile="rootCustomConfig.sh"
			fi

			result2=$(cat $confFile | sed -ne "/^$conf=.*$/ {s/^$conf=\"\(.*\)\"$/\1/ ; p}")
			# in file, the '$' symbols will not be escaped, so we reflect that in our expectancy.
			expectedVal=$(printf "%s" "$expectedVal" | sed -e 's/\\\\\$/$/g')

			if printf "%s" "$result2" | grep -q "$expectedVal"; then
				return 0
			else
				echo "Test : $description -- failed"
				echo "\"$confFile\" does not contain the right configuration entry : \"$conf\" and/or the right value \"$expectedVal\" which should be \"$result2\""
				return 1
			fi
		fi
		return 0
	else
		[ "$reversed" = "true" ] && return 0
		echo "Test : $description -- failed"
		echo "got : '$result' instead of the expected : '$expectedVal'"
		return 1
	fi
}

cd $jail

# Checking if the command 'config' exists
$jtPath config 2>&1 | grep -q 'Invalid command' && exit 1

testGet "Checking if the latest jail config can do config" "networking" "^true$" || exit 1

# done a backup of rootCustomConfig.sh. Will manipulate 'Command part' to be like it was before the upgrade.
cp rootCustomConfig.sh ._rootCustomConfig.sh.bak
sed -e 's/^#* Command part #*/# Command part/' -i rootCustomConfig.sh
testGet -r "initial test with networking" "networking" "" || exit 1
cp ._rootCustomConfig.sh.bak rootCustomConfig.sh

# Will now try to remove 'Command part' completely
sed -e '/^#* Command part #*/ d' -i rootCustomConfig.sh
testGet -r "second test with networking" "networking" "" || exit 1
cp ._rootCustomConfig.sh.bak rootCustomConfig.sh

$jtPath config --get fooBarAvecDuBeurre >/dev/null 2>/dev/null && exit 1
testGet -r "Accessing an invalid configuration name" "fooBarAvecDuBeurre" "" || exit 1

# Checking basic configurations
testGet "jailName" "jailName" "^.\+$" || exit 1
testGet -dp "jailName" "jailName" "^.\+$" || exit 1
testGet -p "extIp" "extIp" "^172.16.0.1$" || exit 1
testGet -dp "default extIp" "extIp" "^172.16.0.1$" || exit 1

# Checking various default configurations
testGet -dp "default jailNet" "jailNet" "^true$" || exit 1
testGet -dp "default createBridge" "createBridge" "^false$" || exit 1
testGet -dp "default networking" "networking" "^false$" || exit 1
testGet -dp "default availableDevices" "availableDevices" "^null random urandom zero$" || exit 1
testGet -dp "default mountSys" "mountSys" "^true$" || exit 1
testGet -dp "default setNetAccess" "setNetAccess" "^false$" || exit 1

# Checking various custom configurations
testGet -p "networking" "networking" '^true$' || exit 1
testGet -p "setNetAccess" "setNetAccess" '^true$' || exit 1

devMountPoints=$(cat << EOF
/dev/dri
/dev/snd
/dev/input
/dev/shm
EOF
)
testGet "devMountPoints" "devMountPoints" "^$devMountPoints$" || exit 1

# Changing a basic configuration
$jtPath config --set extIp 172.16.1.1 >/dev/null || exit 1
testGet -p "extIp" "extIp" '^172.16.1.1$' || exit 1
testGet -dp "default extIp" "extIp" '^172.16.0.1$' || exit 1

$jtPath config --set setNetAccess "true" >/dev/null || exit 1
testGet -p "setNetAccess" "setNetAccess" '^true$' || exit 1
cat rootCustomConfig.sh | grep -q '^setNetAccess="true"$' || exit 1
testGet -dp "default setNetAccess" "setNetAccess" '^false$' || exit 1

# mountSys (have to add to the custom config)
$jtPath config --set mountSys "false" >/dev/null || exit 1
testGet -p "mountSys" "mountSys" "^false$" || exit 1
testGet -dp "mountSys" "mountSys" "^true$" || exit 1

# createBridge (have to add to the custom config)
$jtPath config --set createBridge "true" >/dev/null || exit 1
testGet -p "createBridge (have to add to the custom config)" "createBridge" "^true$" || exit 1
cat rootCustomConfig.sh | grep -q '^createBridge="true"$' || exit 1
testGet -dp "createBridge (have to add to the custom config)" "createBridge" "^false$" || exit 1

new_roMountPoints=$(cat << EOF
/ahah/bleh
/dev
/root
/somePlaceElse/here
EOF
)
$jtPath config --set roMountPoints "$new_roMountPoints" >/dev/null || exit 1
testGet "roMountPoints" "roMountPoints" "^$new_roMountPoints$" || exit 1
$jtPath config --set daemonCommand "/usr/sbin/httpd -p 8000" >/dev/null || exit 1
testGet -p "daemonCommand" "daemonCommand" '^/usr/sbin/httpd -p 8000$' || exit 1

$jtPath config --set daemonCommand "nothing here" >/dev/null || exit 1
$jtPath config --set daemonCommand -- /usr/sbin/httpd -p 8000 >/dev/null || exit 1
testGet -p "daemonCommand without quotes" "daemonCommand" '^/usr/sbin/httpd -p 8000$' || exit 1

# Checking various default configurations again
testGet -dp "default jailNet" "jailNet" "^true$" || exit 1
testGet -dp "default createBridge" "createBridge" "^false$" || exit 1
testGet -dp "default networking" "networking" "^false$" || exit 1
testGet -dp "default availableDevices" "availableDevices" "^null random urandom zero$" || exit 1
testGet -dp "default mountSys" "mountSys" "^true$" || exit 1
testGet -dp "default setNetAccess" "setNetAccess" "^false$" || exit 1

# Checking various custom configurations again
testGet -p "networking" "networking" "^true$" || exit 1
$jtPath config -d --set setNetAccess >/dev/null || exit 1
testGet -dp "setNetAccess to default" "setNetAccess" "^false$" || exit 1
devMountPoints=$(cat << EOF
/dev/dri
/dev/snd
/dev/input
/dev/shm
EOF
)
testGet "devMountPoints" "devMountPoints" "^$devMountPoints$" || exit 1

$jtPath config --set daemonCommand "sh -c \"/usr/sbin/httpd -p 8000\"" >/dev/null || exit 1
testGet -p "with escaped double quotes" "daemonCommand" "^sh -c '/usr/sbin/httpd -p 8000'$" || exit 1

$jtPath config --set daemonCommand 'sh -c "/usr/sbin/httpd -p 8000"' >/dev/null || exit 1
testGet -p "with double quotes inside single quotes" "daemonCommand" "^sh -c '/usr/sbin/httpd -p 8000'$" || exit 1

$jtPath config --set daemonCommand -- sh -c id >/dev/null || exit 1
testGet -p "without englobing quotes" "daemonCommand" '^sh -c id$' || exit 1

$jtPath config --set daemonCommand -- sh -c "/usr/sbin/httpd -p 8000" >/dev/null || exit 1
testGet -p "without englobing quotes but with inner double quotes" "daemonCommand" "^sh -c '/usr/sbin/httpd -p 8000'$" || exit 1

$jtPath config --set daemonCommand -- sh -c '/usr/sbin/httpd -p 8000' >/dev/null || exit 1
testGet -p "without englobing quotes but with inner single quotes" "daemonCommand" "^sh -c '/usr/sbin/httpd -p 8000'$" || exit 1

$jtPath config --set daemonCommand -- sh -c "cd /usr/sbin; httpd -p 8000" >/dev/null || exit 1
testGet -p "without englobing quotes, with inner double quotes and multiple instructions" "daemonCommand" "^sh -c 'cd /usr/sbin; httpd -p 8000'$" || exit 1
cat rootCustomConfig.sh | grep -q "^daemonCommand=\"sh -c 'cd /usr/sbin; httpd -p 8000'\"$" || exit 1

# we basically convert all escaped '$' symbols to '@' and raise an error when '$' is detected after that
testGet -rf 's/\\\$/@/g' "the '$' character must be escaped when outputted" "runEnvironment" '\$' || exit 1

expectedResult="$($jtPath config --get runEnvironment | sed -e 's/\\/\\\\\\/g')"
$jtPath config --set runEnvironment "$expectedResult" >/dev/null
testGet -p "set multiple arguments separated by spaces" "runEnvironment" "$expectedResult" || exit 1

exit 0
