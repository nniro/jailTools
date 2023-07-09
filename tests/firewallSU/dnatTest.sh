#! /bin/sh

rawProto=$1
sh=$2
testPath=$3
jtPath=$4
jail=$5
bb=$6
thisPath=$7

. $testPath/../../utils/utils.sh

if [ "$rawProto" = "udp" ]; then
	proto="udp"
	protoName="Udp"
else
	proto="tcp"
	protoName="Tcp"
fi

# simple test
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat $proto fwTestIn fwTestOut 22 172.16.33.2 9022
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external dnat $proto fwTestIn fwTestOut 22 172.16.33.2 9022;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A PREROUTING -i fwTestIn -p $proto -m $proto --dport 22 -j DNAT --to-destination 172.16.33.2:9022
-A FORWARD -i fwTestIn -o fwTestOut -p $proto -m state --state NEW,RELATED,ESTABLISHED -m $proto --dport 9022 -j ACCEPT
-A FORWARD -i fwTestOut -o fwTestIn -p $proto -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "Simple dnat $proto test failed"
	exit 1
fi
# simple test end

# checks test
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat $proto fwTestIn fwTestOut 22 172.16.33.2 9022 >&2 && exit
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat $proto fwTestIn fwTestOut 22 172.16.33.2 9022
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat $proto fwTestIn fwTestOut 22 172.16.33.2 9022 >&2 || exit
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external dnat $proto fwTestIn fwTestOut 22 172.16.33.2 9022;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A PREROUTING -i fwTestIn -p $proto -m $proto --dport 22 -j DNAT --to-destination 172.16.33.2:9022
-A FORWARD -i fwTestIn -o fwTestOut -p $proto -m state --state NEW,RELATED,ESTABLISHED -m $proto --dport 9022 -j
ACCEPT
-A FORWARD -i fwTestOut -o fwTestIn -p $proto -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "dnat $proto checks test failed"
	exit 1
fi
# checks test

# duplication test
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat $proto fwTestIn fwTestOut 22 172.16.33.2 9022
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat $proto fwTestIn fwTestOut 22 172.16.33.2 9022
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external dnat $proto fwTestIn fwTestOut 22 172.16.33.2 9022;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A PREROUTING -i fwTestIn -p $proto -m $proto --dport 22 -j DNAT --to-destination 172.16.33.2:9022
-A FORWARD -i fwTestIn -o fwTestOut -p $proto -m state --state NEW,RELATED,ESTABLISHED -m $proto --dport 9022 -j ACCEPT
-A FORWARD -i fwTestOut -o fwTestIn -p $proto -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "dnat $proto duplication test failed"
	exit 1
fi
# duplication test end

# duplication with the instruction file removed
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat $proto fwTestIn fwTestOut 22 172.16.33.2 9022

# we remove the entry to see if the function can detect that
# the entries are already there without using the instructions file.
[ -e \$fwInstrPath ] && rm \$fwInstrPath
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat $proto fwTestIn fwTestOut 22 172.16.33.2 9022
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A PREROUTING -i fwTestIn -p $proto -m $proto --dport 22 -j DNAT --to-destination 172.16.33.2:9022
-A FORWARD -i fwTestIn -o fwTestOut -p $proto -m state --state NEW,RELATED,ESTABLISHED -m $proto --dport 9022 -j ACCEPT
-A FORWARD -i fwTestOut -o fwTestIn -p $proto -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "dnat $proto duplication with the instruction file removed test failed"
	exit 1
fi
# duplication with the instruction file removed end

# rule deletion test
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat $proto fwTestIn fwTestOut 22 172.16.33.2 9022
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external dnat $proto fwTestIn fwTestOut 22 172.16.33.2 9022;
EOF

cat - > $jail/root/home/firewallDeleteCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall -d dnat $proto fwTestIn fwTestOut 22 172.16.33.2 9022
EOF

cat - > $jail/root/home/firewallExpectedDeleteInstr << EOF
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A PREROUTING -i fwTestIn -p $proto -m $proto --dport 22 -j DNAT --to-destination 172.16.33.2:9022
-A FORWARD -i fwTestIn -o fwTestOut -p $proto -m state --state NEW,RELATED,ESTABLISHED -m $proto --dport 9022 -j ACCEPT
-A FORWARD -i fwTestOut -o fwTestIn -p $proto -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

cat - > $jail/root/home/runTest.sh << EOF
#! /bin/sh

sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules

#echo Now we delete the inserted rules >&2

sh /home/singleTest.sh -d /home/firewallDeleteCmd /home/firewallExpectedDeleteInstr /home/firewallExpectedIptablesRules
EOF

if ! lift $jtPath start $jail sh /home/runTest.sh 2>/dev/null; then
	echo "dnat $proto deletion test failed"
	exit 1
fi
# rule deletion test end


# protocol specific command name test

# simple test
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat${protoName} fwTestIn fwTestOut 22 172.16.33.2 9022
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external dnat${protoName} fwTestIn fwTestOut 22 172.16.33.2 9022;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A PREROUTING -i fwTestIn -p $proto -m $proto --dport 22 -j DNAT --to-destination 172.16.33.2:9022
-A FORWARD -i fwTestIn -o fwTestOut -p $proto -m state --state NEW,RELATED,ESTABLISHED -m $proto --dport 9022 -j ACCEPT
-A FORWARD -i fwTestOut -o fwTestIn -p $proto -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "Simple dnat${protoName} test failed"
	exit 1
fi

# checks test
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat${protoName} fwTestIn fwTestOut 22 172.16.33.2 9022 >&2 && exit
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat${protoName} fwTestIn fwTestOut 22 172.16.33.2 9022
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat${protoName} fwTestIn fwTestOut 22 172.16.33.2 9022 >&2 || exit
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external dnat${protoName} fwTestIn fwTestOut 22 172.16.33.2 9022;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A PREROUTING -i fwTestIn -p $proto -m $proto --dport 22 -j DNAT --to-destination 172.16.33.2:9022
-A FORWARD -i fwTestIn -o fwTestOut -p $proto -m state --state NEW,RELATED,ESTABLISHED -m $proto --dport 9022 -j
ACCEPT
-A FORWARD -i fwTestOut -o fwTestIn -p $proto -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "dnat${protoName} checks test failed"
	exit 1
fi
# checks test

# duplication test
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat${protoName} fwTestIn fwTestOut 22 172.16.33.2 9022
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat${protoName} fwTestIn fwTestOut 22 172.16.33.2 9022
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external dnat${protoName} fwTestIn fwTestOut 22 172.16.33.2 9022;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A PREROUTING -i fwTestIn -p $proto -m $proto --dport 22 -j DNAT --to-destination 172.16.33.2:9022
-A FORWARD -i fwTestIn -o fwTestOut -p $proto -m state --state NEW,RELATED,ESTABLISHED -m $proto --dport 9022 -j ACCEPT
-A FORWARD -i fwTestOut -o fwTestIn -p $proto -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "dnat${protoName} duplication test failed"
	exit 1
fi
# duplication test end

# duplication with the instruction file removed
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat${protoName} fwTestIn fwTestOut 22 172.16.33.2 9022

# we remove the entry to see if the function can detect that
# the entries are already there without using the instructions file.
[ -e \$fwInstrPath ] && rm \$fwInstrPath
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat${protoName} fwTestIn fwTestOut 22 172.16.33.2 9022
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A PREROUTING -i fwTestIn -p $proto -m $proto --dport 22 -j DNAT --to-destination 172.16.33.2:9022
-A FORWARD -i fwTestIn -o fwTestOut -p $proto -m state --state NEW,RELATED,ESTABLISHED -m $proto --dport 9022 -j ACCEPT
-A FORWARD -i fwTestOut -o fwTestIn -p $proto -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "dnat${protoName} duplication with the instruction file removed test failed"
	exit 1
fi
# duplication with the instruction file removed end

# rule deletion test
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall dnat${protoName} fwTestIn fwTestOut 22 172.16.33.2 9022
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external dnat${protoName} fwTestIn fwTestOut 22 172.16.33.2 9022;
EOF

cat - > $jail/root/home/firewallDeleteCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall -d dnat${protoName} fwTestIn fwTestOut 22 172.16.33.2 9022
EOF

cat - > $jail/root/home/firewallExpectedDeleteInstr << EOF
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A PREROUTING -i fwTestIn -p $proto -m $proto --dport 22 -j DNAT --to-destination 172.16.33.2:9022
-A FORWARD -i fwTestIn -o fwTestOut -p $proto -m state --state NEW,RELATED,ESTABLISHED -m $proto --dport 9022 -j ACCEPT
-A FORWARD -i fwTestOut -o fwTestIn -p $proto -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

cat - > $jail/root/home/runTest.sh << EOF
#! /bin/sh

sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules

#echo Now we delete the inserted rules >&2

sh /home/singleTest.sh -d /home/firewallDeleteCmd /home/firewallExpectedDeleteInstr /home/firewallExpectedIptablesRules
EOF

if ! lift $jtPath start $jail sh /home/runTest.sh 2>/dev/null; then
	echo "dnat${protoName} deletion test failed"
	exit 1
fi
# rule deletion test end

exit 0
