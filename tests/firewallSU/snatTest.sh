#! /bin/sh

sh=$1
testPath=$2
jtPath=$3
jail=$4
bb=$5
thisPath=$6

. $testPath/../../utils/utils.sh

# simple test
cat - > $jail/root/home/firewallCmd << EOF
sh /home/firewallFront.sh \$fwInstrPath firewall snat fwTestOut fwTestIn 172.16.33.2 24
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external snat fwTestOut fwTestIn 172.16.33.2 24;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
:fwTestOut_fwTestIn_masq - \[0:0\]
-A POSTROUTING -o fwTestOut -j fwTestOut_fwTestIn_masq
-A fwTestOut_fwTestIn_masq -s 172.16.33.0/24 -j MASQUERADE
-A FORWARD -i fwTestIn -o fwTestOut -j ACCEPT
-A FORWARD -i fwTestOut -o fwTestIn -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "Simple snat test failed"
	exit 1
fi
# simple test end

# checks test
cat - > $jail/root/home/firewallCmd << EOF
sh /home/firewallFront.sh \$fwInstrPath firewall -c snat fwTestOut fwTestIn 172.16.33.2 24
sh /home/firewallFront.sh \$fwInstrPath firewall snat fwTestOut fwTestIn 172.16.33.2 24
sh /home/firewallFront.sh \$fwInstrPath firewall -c snat fwTestOut fwTestIn 172.16.33.2 24
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external snat fwTestOut fwTestIn 172.16.33.2 24;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
:fwTestOut_fwTestIn_masq - \[0:0\]
-A POSTROUTING -o fwTestOut -j fwTestOut_fwTestIn_masq
-A fwTestOut_fwTestIn_masq -s 172.16.33.0/24 -j MASQUERADE
-A FORWARD -i fwTestIn -o fwTestOut -j ACCEPT
-A FORWARD -i fwTestOut -o fwTestIn -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "snat checks test failed"
	exit 1
fi
# checks test

# duplication test
cat - > $jail/root/home/firewallCmd << EOF
sh /home/firewallFront.sh \$fwInstrPath firewall snat fwTestOut fwTestIn 172.16.33.2 24
sh /home/firewallFront.sh \$fwInstrPath firewall snat fwTestOut fwTestIn 172.16.33.2 24
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external snat fwTestOut fwTestIn 172.16.33.2 24;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
:fwTestOut_fwTestIn_masq - \[0:0\]
-A POSTROUTING -o fwTestOut -j fwTestOut_fwTestIn_masq
-A fwTestOut_fwTestIn_masq -s 172.16.33.0/24 -j MASQUERADE
-A FORWARD -i fwTestIn -o fwTestOut -j ACCEPT
-A FORWARD -i fwTestOut -o fwTestIn -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "snat duplication test failed"
	exit 1
fi
# duplication test end

# duplication with the instruction file removed
cat - > $jail/root/home/firewallCmd << EOF
sh /home/firewallFront.sh \$fwInstrPath firewall snat fwTestOut fwTestIn 172.16.33.2 24

# we remove the entry to see if the function can detect that
# the entries are already there without using the instructions file.
[ -e \$fwInstrPath ] && rm \$fwInstrPath
sh /home/firewallFront.sh \$fwInstrPath firewall snat fwTestOut fwTestIn 172.16.33.2 24
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
:fwTestOut_fwTestIn_masq - \[0:0\]
-A POSTROUTING -o fwTestOut -j fwTestOut_fwTestIn_masq
-A fwTestOut_fwTestIn_masq -s 172.16.33.0/24 -j MASQUERADE
-A FORWARD -i fwTestIn -o fwTestOut -j ACCEPT
-A FORWARD -i fwTestOut -o fwTestIn -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "snat duplication with the instruction file removed test failed"
	exit 1
fi
# duplication with the instruction file removed end

# rule deletion test
cat - > $jail/root/home/firewallCmd << EOF
sh /home/firewallFront.sh \$fwInstrPath firewall snat fwTestOut fwTestIn 172.16.33.2 24
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external snat fwTestOut fwTestIn 172.16.33.2 24;
EOF

cat - > $jail/root/home/firewallDeleteCmd << EOF
sh /home/firewallFront.sh \$fwInstrPath firewall -d snat fwTestOut fwTestIn 172.16.33.2 24
EOF

cat - > $jail/root/home/firewallExpectedDeleteInstr << EOF
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
:fwTestOut_fwTestIn_masq - \[0:0\]
-A POSTROUTING -o fwTestOut -j fwTestOut_fwTestIn_masq
-A fwTestOut_fwTestIn_masq -s 172.16.33.0/24 -j MASQUERADE
-A FORWARD -i fwTestIn -o fwTestOut -j ACCEPT
-A FORWARD -i fwTestOut -o fwTestIn -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

cat - > $jail/root/home/runTest.sh << EOF
#! /bin/sh

sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules

# Now we delete the inserted rules

sh /home/singleTest.sh -d /home/firewallDeleteCmd /home/firewallExpectedDeleteInstr /home/firewallExpectedIptablesRules
EOF

if ! lift $jtPath start $jail sh /home/runTest.sh 2>/dev/null; then
	echo "snat deletion test failed"
	exit 1
fi
# rule deletion test end

exit 0
