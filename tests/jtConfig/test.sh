#! /bin/sh

# this tests the jt config command.

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/jtConfig

$jtPath new $jail 2>&1 >/dev/null || exit 1

cd $jail

echo "Checking if the command 'config' exists"
$jtPath config 2>&1 | grep -q 'Invalid command' && exit 1

echo "Checking if the latest jail config can do config"
$jtPath config --get networking | grep -q '^true$' || exit 1

echo "done a backup of rootCustomConfig.sh. Will manipulate 'Command part' to be like it was before the upgrade."
cp rootCustomConfig.sh ._rootCustomConfig.sh.bak
sed -e 's/^#* Command part #*/# Command part/' -i rootCustomConfig.sh
$jtPath config --get networking >/dev/null 2>/dev/null && exit 1
cp ._rootCustomConfig.sh.bak rootCustomConfig.sh

echo "Will now try to remove 'Command part' completely"
sed -e '/^#* Command part #*/ d' -i rootCustomConfig.sh
$jtPath config --get networking >/dev/null 2>/dev/null && exit 1
cp ._rootCustomConfig.sh.bak rootCustomConfig.sh

echo "Accessing an invalid configuration name"
$jtPath config --get fooBarAvecDuBeurre >/dev/null 2>/dev/null && exit 1

echo "Checking basic configurations"
$jtPath config --get jailName >/dev/null 2>/dev/null || exit 1
$jtPath config --get extIp | grep -q '^172.16.0.1$' || exit 1
$jtPath config --default --get extIp | grep -q '^172.16.0.1$' || exit 1

echo "Checking various default configurations"
echo "default jailNet"
$jtPath config --default --get jailNet | grep -q '^true$' || exit 1
echo "default createBridge"
$jtPath config --default --get createBridge | grep -q '^false$' || exit 1
echo "default networking"
$jtPath config --default --get networking | grep -q '^false$' || exit 1
echo "default availableDevices"
$jtPath config --default --get availableDevices | grep -q "^null urandom zero$" || exit 1
echo "default mountSys"
$jtPath config --default --get mountSys | grep -q '^true$' || exit 1
echo "default setNetAccess"
$jtPath config --default --get setNetAccess | grep -q '^false$' || exit 1

echo "Checking various custom configurations"
echo networking
$jtPath config --get networking | grep -q '^true$' || exit 1
echo setNetAccess
$jtPath config --get setNetAccess | grep -q '^false$' || exit 1
echo "devMountPoints"
devMountPoints=$(cat << EOF
/dev/dri
/dev/snd
/dev/input
/dev/shm
EOF
)
$jtPath config --get devMountPoints | grep -q "^$devMountPoints$" || exit 1

echo "Changing a basic configuration"
echo "extIp"
$jtPath config --set extIp 172.16.1.1 || exit 1
$jtPath config --get extIp | grep -q '^172.16.1.1$' || exit 1
$jtPath config --default --get extIp | grep -q '^172.16.0.1$' || exit 1
echo "setNetAccess"
$jtPath config --set setNetAccess "true" || exit 1
$jtPath config --get setNetAccess | grep -q '^true$' || exit 1
cat rootCustomConfig.sh | grep -q '^setNetAccess="true"$' || exit 1
$jtPath config --default --get setNetAccess | grep -q '^false$' || exit 1
echo "mountSys (have to add to the custom config)"
$jtPath config --set mountSys "false" || exit 1
$jtPath config --get mountSys | grep -q '^false$' || exit 1
$jtPath config --default --get mountSys | grep -q '^true$' || exit 1
echo "createBridge (have to add to the custom config)"
$jtPath config --set createBridge "true" || exit 1
$jtPath config --get createBridge | grep -q '^true$' || exit 1
cat rootCustomConfig.sh | grep -q '^createBridge="true"$' || exit 1
$jtPath config --default --get createBridge | grep -q '^false$' || exit 1
echo "roMountPoints"
new_roMountPoints=$(cat << EOF
/ahah/bleh
/dev
/root
/somePlaceElse/here
EOF
)
$jtPath config --set roMountPoints "$new_roMountPoints" || exit 1
$jtPath config --get roMountPoints | grep -q "^$new_roMountPoints$" || exit 1
echo "daemonCommand"
$jtPath config --set daemonCommand "/usr/sbin/httpd -p 8000" || exit 1
$jtPath config --get daemonCommand | grep -q '^/usr/sbin/httpd -p 8000$' || exit 1
echo "daemonCommand without quotes"
$jtPath config --set daemonCommand "nothing here" || exit 1
$jtPath config --set daemonCommand -- /usr/sbin/httpd -p 8000 || exit 1
$jtPath config --get daemonCommand | grep -q '^/usr/sbin/httpd -p 8000$' || exit 1
cat rootCustomConfig.sh | grep -q '^daemonCommand="/usr/sbin/httpd -p 8000"$' || exit 1

echo "Checking various default configurations again"
echo "default jailNet"
$jtPath config --default --get jailNet | grep -q '^true$' || exit 1
echo "default createBridge"
$jtPath config --default --get createBridge | grep -q '^false$' || exit 1
echo "default networking"
$jtPath config --default --get networking | grep -q '^false$' || exit 1
echo "default availableDevices"
$jtPath config --default --get availableDevices | grep -q "^null urandom zero$" || exit 1
echo "default mountSys"
$jtPath config --default --get mountSys | grep -q '^true$' || exit 1
echo "default setNetAccess"
$jtPath config --default --get setNetAccess | grep -q '^false$' || exit 1

echo "Checking various custom configurations again"
echo networking
$jtPath config --get networking | grep -q '^true$' || exit 1
echo setNetAccess to default
$jtPath config -d --set setNetAccess || exit 1
$jtPath config --get setNetAccess | grep -q '^false$' || exit 1
echo "devMountPoints"
devMountPoints=$(cat << EOF
/dev/dri
/dev/snd
/dev/input
/dev/shm
EOF
)
$jtPath config --get devMountPoints | grep -q "^$devMountPoints$" || exit 1

echo "with escaped double quotes"
$jtPath config --set daemonCommand "sh -c \"/usr/sbin/httpd -p 8000\"" || exit 1
$jtPath config --get daemonCommand
$jtPath config --get daemonCommand | grep -q "^sh -c '/usr/sbin/httpd -p 8000'$" || exit 1

echo "with double quotes inside single quotes"
$jtPath config --set daemonCommand 'sh -c "/usr/sbin/httpd -p 8000"' || exit 1
$jtPath config --get daemonCommand | grep -q "^sh -c '/usr/sbin/httpd -p 8000'$" || exit 1

echo "without englobing quotes"
$jtPath config --set daemonCommand -- sh -c id || exit 1
$jtPath config --get daemonCommand | grep -q '^sh -c id$' || exit 1

echo "without englobing quotes but with inner double quotes"
$jtPath config --set daemonCommand -- sh -c "/usr/sbin/httpd -p 8000" || exit 1
$jtPath config --get daemonCommand | grep -q "^sh -c '/usr/sbin/httpd -p 8000'$" || exit 1

echo "without englobing quotes but with inner single quotes"
$jtPath config --set daemonCommand -- sh -c '/usr/sbin/httpd -p 8000' || exit 1
$jtPath config --get daemonCommand | grep -q "^sh -c '/usr/sbin/httpd -p 8000'$" || exit 1

echo "without englobing quotes, with inner double quotes and multiple instructions"
$jtPath config --set daemonCommand -- sh -c "cd /usr/sbin; httpd -p 8000" || exit 1
$jtPath config --get daemonCommand | grep -q "^sh -c 'cd /usr/sbin; httpd -p 8000'$" || exit 1
cat rootCustomConfig.sh | grep -q "^daemonCommand=\"sh -c 'cd /usr/sbin; httpd -p 8000'\"$" || exit 1

echo "the '$' character must be escaped when outputted"
# we basically convert all escaped '$' symbols to '@' and raise an error when '$' is detected after that
$jtPath config --get runEnvironment | sed -e 's/\\\$/@/g' | grep -q '\$' && exit 1

echo "set multiple arguments separated by spaces"
expectedResult=$($jtPath config --get runEnvironment)
$jtPath config --set runEnvironment "$expectedResult"
$jtPath config --get runEnvironment | grep -q "$expectedResult" || exit 1

exit 0
