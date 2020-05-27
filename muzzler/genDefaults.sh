#! /bin/sh

ownPath=$(dirname $0)

rawData=$(cat $ownPath/../usr/include/bits/syscall.h | sed -ne '/#define __NR_/ s/^#define __NR_\(.*\)$/\1/ p')

mainData=$(printf "%s" "$rawData" | sed -e 's/\( \|\t\)\+/\@/g')

curCount=$(echo $mainData | sed -e 's/ /\n/g' | sed -e '/^$/ d' | wc -l)

cat << EOF
/* This file is generated automatically, don't edit it. */

#ifndef __PRESETS_H
#define __PRESETS_H

typedef struct Syscall {
	char *name;
	int index;
}Syscall;

typedef struct Preset Preset;

struct Preset {
	char *name;
	char *description;
	int syscallCount;
	const Syscall *syscalls;

	int presetCount;
	const Preset **presets;
};

/* state values -- 0 : unset, 1 : allow, 2 : disallow */
char syscallState[$curCount];

EOF

availSyscallPresets=""

cleanup() {
	# remove empty lines and all comments
	sed -e '/^$/ d; /^#/ d; s/#.*$//'
}

parseSection() {
	local sectionName=$1
	local isActive=$2
	local inputFile=$3

	if [ "$isActive" = "true" ]; then
		#echo "$sectionName section : "
		cat $inputFile | cleanup | sed -ne "/^\[$sectionName\]/ {s/\[$sectionName\]// ; be}; b; :e ; $ {p; q}; /\[/ {s/\[.*\]// ; p; q}; N; be" | cleanup
	fi
}

# create filter prototypes so they can be linked correctly
echo "/* Filter Prototypes */"
for preset in $(ls $ownPath/presets | sed -ne '/.*\~/ ! p'); do
	if echo $@ | grep -q "$preset" || echo $@ | grep -q '^$'; then
		echo "const Preset ${preset}Filter;"
	fi
done

echo

echo "const Syscall syscallList[$(echo $mainData | sed -e 's/ /\n/g' | wc -l)] = {"
for rawSyscall in $mainData; do
	syscall=$(echo $rawSyscall | sed -e 's/^\([^@]*\)@.*$/\1/')
	syscallNum=$(echo $rawSyscall | sed -e 's/^[^@]*@\(.*\)$/\1/')
	echo "	$comma{\"$syscall\", $syscallNum}"
	comma=","
done
echo "};"

echo

for preset in $(ls $ownPath/presets | sed -ne '/.*\~/ ! p'); do
	hasConfig=false
	hasSyscalls=false
	hasPresets=false
	toParse="$ownPath/presets/$preset"
	grep -q '^\[config\]' $toParse && hasConfig=true
	grep -q '^\[syscalls\]' $toParse && hasSyscalls=true
	grep -q '^\[presets\]' $toParse && hasPresets=true

	configData=$(parseSection "config" $hasConfig $toParse)
	syscallsData=$(parseSection "syscalls" $hasSyscalls $toParse)
	presetsData=$(parseSection "presets" $hasPresets $toParse)

	if [ "$hasSyscalls" = "true" ]; then
		curFilter=$(echo $syscallsData | sed -ne ':e ; $ {p; q}; N; s/\n/ /g; be' | sed -e 's/ /\\|/g' | sed -e 's/\(.*\)/\\(\1\\)/')
		syscalls=$(echo $mainData | sed -e 's/ /\n/g' | sed -ne "/$curFilter/ p")
		mainData=$(echo $mainData | sed -e 's/ /\n/g' | sed -ne "/$curFilter/ ! p")

		lastCount=$curCount
		curCount=$(echo $mainData | sed -e 's/ /\n/g' | sed -e '/^$/ d' | wc -l)
	fi

	description=""
	[ "$hasConfig" = "true" ] && description=$(echo $configData | sed -ne '/^description=/ {s/^description=\(.*\)$/\1/ ;p; q}')

	if echo $@ | grep -q "$preset" || echo $@ | grep -q '^$'; then
		syscallCount=0
		syscallListName=NULL
		if [ "$hasSyscalls" = "true" ]; then
			comma=""
			syscallCount=$(($lastCount - $curCount))
			syscallListName=${preset}SyscallList
			echo "const Syscall ${syscallListName}[$syscallCount] = {"
			for rawSyscall in $syscalls; do
				syscall=$(echo $rawSyscall | sed -e 's/^\([^@]*\)@.*$/\1/')
				syscallNum=$(echo $rawSyscall | sed -e 's/^[^@]*@\(.*\)$/\1/')
				echo "	$comma{\"$syscall\", $syscallNum}"
				comma=","
			done
			echo "};"
		fi

		presetCount=0
		presetListName=NULL
		if [ "$hasPresets" = "true" ]; then
			comma=""
			presetCount=$(echo $presetsData | sed -e 's/ /\n/g' | wc -l)
			presetListName=${preset}PresetList
			echo "const Preset *${presetListName}[$presetCount] = {"
			for curPreset in $presetsData; do
				echo "	${comma}&${curPreset}Filter"
				comma=","
			done
			echo "};"
		fi

		echo "const Preset ${preset}Filter = {\"$preset\", \"$description\", $syscallCount, $syscallListName, $presetCount, $presetListName};"

		[ "$availSyscallPresets" != "" ] && availSyscallPresets="$availSyscallPresets $preset" || availSyscallPresets="$preset"
		echo
	fi
done


comma=""
echo "const Preset *availSyscallPresets[$(echo $availSyscallPresets | sed -e 's/ /\n/g' | wc -l)] = {"
for availPreset in $availSyscallPresets; do
	echo "	${comma}&${availPreset}Filter"
	comma=","
done
echo "};"

cat << EOF

#endif /* NOT __PRESETS_H */
EOF

[ "$mainData" = "" ] || echo $mainData >&2
