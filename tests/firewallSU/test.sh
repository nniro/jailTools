#! /bin/sh

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/fwTest

bb=$testPath/../bin/busybox

. $testPath/../../utils/utils.sh

$jtPath new $jail >/dev/null 2>/dev/null || exit 1

$jtPath config $jail -s realRootInJail true >/dev/null 2>/dev/null

cat - > $jail/root/home/firewallFront.sh << EOF
#! /bin/sh

eval "\$(jt --show jt_firewall)"

firewallCLI \$@

exit \$?

EOF

$jtPath cp $jail /usr/sbin /usr/sbin/iptables /usr/sbin/iptables-save

$jtPath config $jail -s runEnvironment "PATH=\"/sbin:/usr/sbin:/bin:/usr/bin\" $($jtPath config $jail -g runEnvironment)" >/dev/null 2>/dev/null

$jtPath config $jail -s networking true >/dev/null 2>/dev/null
$jtPath config $jail -s setNetAccess false >/dev/null 2>/dev/null

#lift $jtPath daemon $jail >/dev/null 2>/dev/null || exit 1
#$bb timeout 30 sh -c 'while :; do if [ -e run/jail.pid ]; then break; fi ; done'

#if [ ! -e $jail/run/jail.pid ]; then
#	echo "The daemonized jail is not running, run/jail.pid is missing"
#	exit 1
#fi

#lift $jtPath stop $jail
#sleep 1
#sleep 5

#exit 0

# preparation done

# first test

# we make a simple attempt at blockAll and check if the
# result is what we expect.

cat - > $jail/root/home/testUtils.sh << EOF
checkLines() {
        for l in \$1; do
                #echo "entry : '\$l'"
                count=\$(printf "%s" "\$2" | grep -- "^\$l$" | wc -l)

                if [ "\$count" = "0" ]; then
                        echo "\$l - Not present"
                        return 1
                elif [ \$((\$count > 1)) = 1 ]; then
                        echo "\$l - More than one entry detected"
                        return 1
                fi
        done
}
EOF

cat - > $jail/root/home/currentTest.sh << EOF
. /home/testUtils.sh

cd /home

fwInstrPath=/tmp/firewallInstructions.txt

[ -e \$fwInstrPath ] && rm \$fwInstrPath

sh /home/firewallFront.sh \$fwInstrPath firewall blockAll fwTestIn fwTestIn

if [ ! -e \$fwInstrPath ]; then
	echo "file '\$fwInstrPath' should exist but it doesn't"
	exit 1
fi

if ! cat \$fwInstrPath | grep -q "firewall /tmp/firewallInstructions.txt external blockAll fwTestIn fwTestIn;"; then
	echo "The file firewallInstructions.txt has an unexpected content '\$(cat \$fwInstrPath)'"
	exit 1
fi

expectedResultLines=\$(cat - << HEREDOC
-A INPUT -i fwTestIn -p tcp -m tcp --dport 1:65535 -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
-A INPUT -i fwTestIn -p udp -m udp --dport 1:65535 -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
-A OUTPUT -o fwTestIn -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
HEREDOC
)

result=\$(iptables-save)
IFS="
"
if ! checkLines "\$expectedResultLines" "\$result"; then
	echo "result from iptables-save : '\$result'"
	exit 1
fi
EOF

if ! lift $jtPath start $jail sh /home/currentTest.sh 2>/dev/null; then
	echo "Simple blockAll check failed"
	exit 1
fi

# test if the check functionnality works correctly
cat - > $jail/root/home/currentTest.sh << EOF
. /home/testUtils.sh

cd /home

fwInstrPath=/tmp/firewallInstructions.txt

[ -e \$fwInstrPath ] && rm \$fwInstrPath

sh /home/firewallFront.sh \$fwInstrPath firewall -c blockAll fwTestIn fwTestIn && exit 1


sh /home/firewallFront.sh \$fwInstrPath firewall blockAll fwTestIn fwTestIn

if [ ! -e \$fwInstrPath ]; then
	echo "file '\$fwInstrPath' should exist but it doesn't"
	exit 1
fi

if ! cat \$fwInstrPath | grep -q "firewall /tmp/firewallInstructions.txt external blockAll fwTestIn fwTestIn;"; then
	echo "The file firewallInstructions.txt has an unexpected content '\$(cat \$fwInstrPath)'"
	exit 1
fi

sh /home/firewallFront.sh \$fwInstrPath firewall -c blockAll fwTestIn fwTestIn || exit 1

expectedResultLines=\$(cat - << HEREDOC
-A INPUT -i fwTestIn -p tcp -m tcp --dport 1:65535 -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
-A INPUT -i fwTestIn -p udp -m udp --dport 1:65535 -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
-A OUTPUT -o fwTestIn -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
HEREDOC
)

result=\$(iptables-save)
IFS="
"
if ! checkLines "\$expectedResultLines" "\$result"; then
	echo "result from iptables-save : '\$result'"
	exit 1
fi
EOF

if ! lift $jtPath start $jail sh /home/currentTest.sh 2>/dev/null; then
	echo "The check functionnality does not work correctly"
	exit 1
fi


# check for duplication when running blockAll twice

cat - > $jail/root/home/currentTest2.sh << EOF
. /home/testUtils.sh

cd /home

fwInstrPath=/tmp/firewallInstructions.txt

[ -e \$fwInstrPath ] && rm \$fwInstrPath

sh /home/firewallFront.sh \$fwInstrPath firewall blockAll fwTestIn fwTestIn
sh /home/firewallFront.sh \$fwInstrPath firewall blockAll fwTestIn fwTestIn

if [ ! -e \$fwInstrPath ]; then
	echo "file '\$fwInstrPath' should exist but it doesn't"
	exit 1
fi

if ! cat \$fwInstrPath | grep -q "firewall /tmp/firewallInstructions.txt external blockAll fwTestIn fwTestIn;"; then
	echo "The file firewallInstructions.txt has an unexpected content '\$(cat \$fwInstrPath)'"
	exit 1
fi

expectedResultLines=\$(cat - << HEREDOC
-A INPUT -i fwTestIn -p tcp -m tcp --dport 1:65535 -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
-A INPUT -i fwTestIn -p udp -m udp --dport 1:65535 -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
-A OUTPUT -o fwTestIn -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
HEREDOC
)

result=\$(iptables-save)
IFS="
"
if ! checkLines "\$expectedResultLines" "\$result"; then
	echo "result from iptables-save : '\$result'"
	exit 1
fi
EOF

if ! lift $jtPath start $jail sh /home/currentTest2.sh 2>/dev/null; then
	echo "Duplicate check blockAll failed"
	exit 1
fi

# check for duplication when running blockAll twice
# we remove the entry from the instruction file.

cat - > $jail/root/home/currentTest3.sh << EOF
. /home/testUtils.sh

cd /home

fwInstrPath=/tmp/firewallInstructions.txt

[ -e \$fwInstrPath ] && rm \$fwInstrPath

sh /home/firewallFront.sh \$fwInstrPath firewall blockAll fwTestIn fwTestIn

# we remove the entry to see if the function can detect that
# the entries are already there without using the instructions file.
[ -e \$fwInstrPath ] && rm \$fwInstrPath
sh /home/firewallFront.sh \$fwInstrPath firewall blockAll fwTestIn fwTestIn

if [ ! -e \$fwInstrPath ]; then
	echo "file '\$fwInstrPath' should exist but it doesn't"
	exit 1
fi

# we expect the file to contain nothing
if test -s \$fwInstrPath; then
	echo "The file firewallInstructions.txt has an unexpected content '\$(cat \$fwInstrPath)'"
	exit 1
fi

expectedResultLines=\$(cat - << HEREDOC
-A INPUT -i fwTestIn -p tcp -m tcp --dport 1:65535 -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
-A INPUT -i fwTestIn -p udp -m udp --dport 1:65535 -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
-A OUTPUT -o fwTestIn -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
HEREDOC
)

result=\$(iptables-save)
IFS="
"
if ! checkLines "\$expectedResultLines" "\$result"; then
	echo "result from iptables-save : '\$result'"
	exit 1
fi
EOF

if ! lift $jtPath start $jail sh /home/currentTest3.sh 2>/dev/null; then
	echo "Duplicate check blockAll failed after entry removed from the instruction file"
	exit 1
fi

exit 0
