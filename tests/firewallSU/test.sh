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

cat - > $jail/root/home/singleTest.sh << EOF
. /home/testUtils.sh

cmdFile=\$1
expectedInstrRuleFile=\$2
expectedIptablesRulesFile=\$3
shift 3

if [ ! -e \$cmdFile ]; then
	echo cmdFile missing
	exit 1
fi

if [ ! -e \$expectedInstrRuleFile ]; then
	echo expectedInstrRuleFile missing
	exit 1
fi

if [ ! -e \$expectedIptablesRuleFile ]; then
	echo expectedIptablesRulesFile missing
	exit 1
fi

cd /home

fwInstrPath=/tmp/firewallInstructions.txt

[ -e \$fwInstrPath ] && rm \$fwInstrPath

#sh \$cmdFile
. \$cmdFile

if [ ! -e \$fwInstrPath ]; then
	echo "file '\$fwInstrPath' should exist but it doesn't"
	exit 1
fi

if ! test -s \$expectedInstrRuleFile; then
	# we expect the instruction file to contain nothing
	if test -s \$fwInstrPath; then
		echo "The file firewallInstructions.txt has an unexpected content '\$(cat \$fwInstrPath)'"
		exit 1
	fi
else
	if ! cat \$fwInstrPath | grep -q "^\$(cat \$expectedInstrRuleFile)$"; then
		echo "The file firewallInstructions.txt has an unexpected content '\$(cat \$fwInstrPath)'"
		exit 1
	fi
fi

result=\$(iptables-save)
IFS="
"
if ! checkLines "\$(cat \$expectedIptablesRulesFile)" "\$result"; then
	echo "result from iptables-save : '\$result'"
	exit 1
fi
EOF

# simple blockAll test
cat - > $jail/root/home/firewallCmd << EOF
sh /home/firewallFront.sh \$fwInstrPath firewall blockAll fwTestIn fwTestIn
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external blockAll fwTestIn fwTestIn;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A INPUT -i fwTestIn -p tcp -m tcp --dport 1:65535 -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
-A INPUT -i fwTestIn -p udp -m udp --dport 1:65535 -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
-A OUTPUT -o fwTestIn -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "Simple blockAll test failed"
	exit 1
fi
# simple blockAll test end

# blockAll checks test
cat - > $jail/root/home/firewallCmd << EOF
sh /home/firewallFront.sh \$fwInstrPath firewall -c blockAll fwTestIn fwTestIn && exit 1
sh /home/firewallFront.sh \$fwInstrPath firewall blockAll fwTestIn fwTestIn
sh /home/firewallFront.sh \$fwInstrPath firewall -c blockAll fwTestIn fwTestIn || exit 1
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external blockAll fwTestIn fwTestIn;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A INPUT -i fwTestIn -p tcp -m tcp --dport 1:65535 -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
-A INPUT -i fwTestIn -p udp -m udp --dport 1:65535 -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
-A OUTPUT -o fwTestIn -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "blockAll checks test failed"
	exit 1
fi
# blockAll checks test

# blockAll duplication test
cat - > $jail/root/home/firewallCmd << EOF
sh /home/firewallFront.sh \$fwInstrPath firewall blockAll fwTestIn fwTestIn
sh /home/firewallFront.sh \$fwInstrPath firewall blockAll fwTestIn fwTestIn
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external blockAll fwTestIn fwTestIn;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A INPUT -i fwTestIn -p tcp -m tcp --dport 1:65535 -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
-A INPUT -i fwTestIn -p udp -m udp --dport 1:65535 -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
-A OUTPUT -o fwTestIn -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "blockAll duplication test failed"
	exit 1
fi
# blockAll duplication test end

# blockAll duplication with the instruction file removed
cat - > $jail/root/home/firewallCmd << EOF
sh /home/firewallFront.sh \$fwInstrPath firewall blockAll fwTestIn fwTestIn

# we remove the entry to see if the function can detect that
# the entries are already there without using the instructions file.
[ -e \$fwInstrPath ] && rm \$fwInstrPath
sh /home/firewallFront.sh \$fwInstrPath firewall blockAll fwTestIn fwTestIn
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A INPUT -i fwTestIn -p tcp -m tcp --dport 1:65535 -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
-A INPUT -i fwTestIn -p udp -m udp --dport 1:65535 -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
-A OUTPUT -o fwTestIn -m state ! --state RELATED,ESTABLISHED -j REJECT --reject-with icmp-port-unreachable
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "blockAll duplication with the instruction file removed test failed"
	exit 1
fi
# blockAll duplication with the instruction file removed end

exit 0
