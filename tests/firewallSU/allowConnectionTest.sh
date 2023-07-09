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
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall allowConnection $proto fwTestOut 172.16.0.2 8000
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external allowConnection $proto fwTestOut 172.16.0.2 8000;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A OUTPUT -d 172.16.0.2/32 -o fwTestOut -p $proto -m $proto --dport 8000 -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "Simple allowConnection $proto test failed"
	exit 1
fi
# simple test end

# checks test
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall -c allowConnection $proto fwTestOut 172.16.0.2 8000 >&2 && exit 1
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall allowConnection $proto fwTestOut 172.16.0.2 8000
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall -c allowConnection $proto fwTestOut 172.16.0.2 8000 >&2 || exit 1
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external allowConnection $proto fwTestOut 172.16.0.2 8000;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A OUTPUT -d 172.16.0.2/32 -o fwTestOut -p $proto -m $proto --dport 8000 -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "allowConnection $proto checks test failed"
	exit 1
fi
# checks test

# duplication test
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall allowConnection $proto fwTestOut 172.16.0.2 8000
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall allowConnection $proto fwTestOut 172.16.0.2 8000
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external allowConnection $proto fwTestOut 172.16.0.2 8000;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A OUTPUT -d 172.16.0.2/32 -o fwTestOut -p $proto -m $proto --dport 8000 -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "allowConnection $proto duplication test failed"
	exit 1
fi
# duplication test end

# duplication with the instruction file removed
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall allowConnection $proto fwTestOut 172.16.0.2 8000

# we remove the entry to see if the function can detect that
# the entries are already there without using the instructions file.
[ -e \$fwInstrPath ] && rm \$fwInstrPath
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall allowConnection $proto fwTestOut 172.16.0.2 8000
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A OUTPUT -d 172.16.0.2/32 -o fwTestOut -p $proto -m $proto --dport 8000 -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "allowConnection $proto duplication with the instruction file removed test failed"
	exit 1
fi
# duplication with the instruction file removed end

# rule deletion test
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall allowConnection $proto fwTestOut 172.16.0.2 8000
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external allowConnection $proto fwTestOut 172.16.0.2 8000;
EOF

cat - > $jail/root/home/firewallDeleteCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall -d allowConnection $proto fwTestOut 172.16.0.2 8000
EOF

cat - > $jail/root/home/firewallExpectedDeleteInstr << EOF
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A OUTPUT -d 172.16.0.2/32 -o fwTestOut -p $proto -m $proto --dport 8000 -j ACCEPT
EOF

cat - > $jail/root/home/runTest.sh << EOF
#! /bin/sh

sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules

#echo Now we delete the inserted rules >&2

sh /home/singleTest.sh -d /home/firewallDeleteCmd /home/firewallExpectedDeleteInstr /home/firewallExpectedIptablesRules
EOF

if ! lift $jtPath start $jail sh /home/runTest.sh 2>/dev/null; then
	echo "allowConnection $proto deletion test failed"
	exit 1
fi
# rule deletion test end


# protocol specific command name test

# simple test
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall allow${protoName}Connection fwTestOut 172.16.0.2 8000
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external allow${protoName}Connection fwTestOut 172.16.0.2 8000;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A OUTPUT -d 172.16.0.2/32 -o fwTestOut -p $proto -m $proto --dport 8000 -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "Simple allow${protoName}Connection test failed"
	exit 1
fi
# simple test end

# checks test
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall -c allow${protoName}Connection fwTestOut 172.16.0.2 8000 >&2 && exit 1
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall allow${protoName}Connection fwTestOut 172.16.0.2 8000
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall -c allow${protoName}Connection fwTestOut 172.16.0.2 8000 >&2 || exit 1
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external allow${protoName}Connection fwTestOut 172.16.0.2 8000;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A OUTPUT -d 172.16.0.2/32 -o fwTestOut -p $proto -m $proto --dport 8000 -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "allow${protoName}Connection checks test failed"
	exit 1
fi
# checks test

# duplication test
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall allow${protoName}Connection fwTestOut 172.16.0.2 8000
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall allow${protoName}Connection fwTestOut 172.16.0.2 8000
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external allow${protoName}Connection fwTestOut 172.16.0.2 8000;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A OUTPUT -d 172.16.0.2/32 -o fwTestOut -p $proto -m $proto --dport 8000 -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "allow${protoName}Connection duplication test failed"
	exit 1
fi
# duplication test end

# duplication with the instruction file removed
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall allow${protoName}Connection fwTestOut 172.16.0.2 8000

# we remove the entry to see if the function can detect that
# the entries are already there without using the instructions file.
[ -e \$fwInstrPath ] && rm \$fwInstrPath
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall allow${protoName}Connection fwTestOut 172.16.0.2 8000
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A OUTPUT -d 172.16.0.2/32 -o fwTestOut -p $proto -m $proto --dport 8000 -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "allow${protoName}Connection duplication with the instruction file removed test failed"
	exit 1
fi
# duplication with the instruction file removed end

# rule deletion test
cat - > $jail/root/home/firewallCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall allow${protoName}Connection fwTestOut 172.16.0.2 8000
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external allow${protoName}Connection fwTestOut 172.16.0.2 8000;
EOF

cat - > $jail/root/home/firewallDeleteCmd << EOF
/usr/bin/jt --run jt_firewall \$fwInstrPath firewall -d allow${protoName}Connection fwTestOut 172.16.0.2 8000
EOF

cat - > $jail/root/home/firewallExpectedDeleteInstr << EOF
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A OUTPUT -d 172.16.0.2/32 -o fwTestOut -p $proto -m $proto --dport 8000 -j ACCEPT
EOF

cat - > $jail/root/home/runTest.sh << EOF
#! /bin/sh

sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules

# Now we delete the inserted rules

sh /home/singleTest.sh -d /home/firewallDeleteCmd /home/firewallExpectedDeleteInstr /home/firewallExpectedIptablesRules
EOF

if ! lift $jtPath start $jail sh /home/runTest.sh 2>/dev/null; then
	echo "allow${protoName}Connection deletion test failed"
	exit 1
fi
# rule deletion test end

exit 0
