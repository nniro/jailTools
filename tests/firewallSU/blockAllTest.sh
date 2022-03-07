#! /bin/sh

sh=$1
testPath=$2
jtPath=$3
jail=$4
bb=$5
thisPath=$6

. $testPath/../../utils/utils.sh

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
