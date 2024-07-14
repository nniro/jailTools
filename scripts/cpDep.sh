# copy files and its dependencies to a jail (for shared objects or shared binaries).
#
# direct call :
# jt --run jt_cpDep
#
bb="$BB"
shower="$JT_SHOWER"
runner="$JT_RUNNER"

if [ $(($# < 3)) = 1 ]; then
	echo "Synopsis: $0 <jail path> <destination directory inside the jail> [file ...]"
	echo "please input a destination jail, a destination and files or directories to compute and copy"
	exit 1
fi

isJail=0
destJail=$1
destInJail=$2
debugging=0
shift 2
files=$@

ownPath=$($bb dirname $0)

if bb=$bb $runner jt_utils isValidJailPath $destJail; then
	isJail=1
	destJail=$destJail/root
else
	echo "destination PATH is either not a valid jail directory or doesn't exist." >&2
	exit 1
fi

createNewDir () {
	local distDir=$1

	local parent=$($bb dirname $distDir)

	[ "$debugging" = "1" ] && echo "DEBUG ----- $distDir"
	if [ ! -d $distDir ]; then
		createNewDir $parent
		[ "$debugging" = "1" ] && echo "$distDir -> directory $distDir doesn't exist"
		[ "$debugging" = "1" ] && echo "$distDir -> creating directory $distDir"
		if [ "$debugging" = "1" ]; then
			$bb mkdir $distDir
		else
			$bb mkdir $distDir 2>/dev/null
		fi
	else
		[ "$debugging" = "1" ] && echo "$distDir -> directory $parent exists"
	fi
}

safeCopyFile () {
	local src=$1
	local dstDir=$2
	local dstPath=$3
	[ "$debugging" = "1" ] && echo "safeCopyFile : src=$src dstDir=$dstDir dstPath=$dstPath"
	if [ -h $src ]; then # symbolic link check
		# this ensures that the file that the link points to is also copied
		link=$($bb readlink $src)
		if [ "$($bb dirname $link)" = "." ]; then
			link="$($bb dirname $src)/$link"
		fi
		if [ ! -e $link ]; then # in case the link is relative and not absolute
			link="$($bb dirname $src)/$link"
		fi
		[ "$debugging" = "1" ] && echo $src is a link to $link
		safeCopyFile "$link" "$dstDir" "$($bb dirname $link)"
		[ "$debugging" = "1" ] && echo "done copying link"
	fi

	local dstPathCmp=$dstDir/$dstPath/$($bb basename $src)
	if 	[ ! -e $dstPathCmp ] || # if it just doesn't exist we copy it
		([ -e $dstPathCmp ] && [ ! -h $src ] && [ -h $dstPathCmp ]) ||  # this is in case our destination is actually a link, so we replace it with a real file
		([ -e $dstPathCmp ] && [ -h $src ] && [ ! -h $dstPathCmp ]) ||  # this is in case our destination is not a link, so we replace it with a link
		[ $dstPathCmp -ot $src ]; then # this is in case the destination does not exist or it is older than the origin
		createNewDir "$dstDir/$dstPath"
		[ "$debugging" = "1" ] && echo "copying $src -> $dstPathCmp"
		$bb cp -f -p $src $dstPathCmp 2>/dev/null >/dev/null
	else # destination file already exists
		:
	fi
}

compDeps() {
	file=$1

	example="\
		linux-gate.so.1 (0xb77a2000)\n\
		libc.so.6 => /lib/libc.so.6 (0xb75c9000)\n\
		/lib/ld-linux.so.2 (0xb77a3000)\
	"

	if [ "$file" = "" ]; then
		echo "Please input an executable file or shared object."
		exit 1
	fi

	if [ ! -e $file ]; then
		echo "Error, no such file or directory: $file"
		exit 1
	fi

	rawOutput=$($runner jt_readElf -d $file) || exit 1

	[ "$rawOutput" = "" ] && return

	printf "%s" "$rawOutput" | $bb sed -e "s/^\(\|[ \t]*\)\([^ ]*\) (.*)$/\2/" -e "s/[^ ]* \=> \([^ ]*\) (.*)$/\1/" | $bb sed -e "/\(linux-gate\|linux-vdso\)/ d"
}

handle_files () {
	local finalDest=$1

	#echo about to recurse those input values : $1
	for i in $(echo "$2"); do
		if [ ! -e $i ]; then
			installedPath=$($bb which $i) # handle installed binaries

			if [ "$installedPath" = "" ]; then
				[ "$debugging" = "1" ] && echo "$i - No Such file or directory"
				continue
			else
				i=$installedPath
			fi
		fi
		#echo cycle $i
		if [ -d $i ]; then
			[ "$debugging" = "1" ] && echo recursively handle the directory $i
			#echo "Next cycle destination : $finalDest/$($bb basename $i)"
			handle_files "$finalDest/$($bb basename $i)" "$($bb ls -d $i/*)"
			continue
		fi

		# the dependencies are copied first
		deps=$(compDeps $i)
		for t in $deps; do
			#break;
			if [ -e $t ]; then
				safeCopyFile "$t" "$destJail" "$($bb dirname $t)"
			fi
		done

		# the actual directory or files are now copied
		#echo "Debug : $i -> $finalDest"
		safeCopyFile "$i" "$destJail" "$finalDest"
	done
}

handle_files "$destInJail" "$files"

if [ "$isJail" = "1" ]; then
	# parent
	pDir=$($bb dirname $destJail)
	scriptName=$($bb basename $0)

	if [ ! -e $pDir/update.sh ]; then
		jtPath=""

		if [ "$(echo $ownPath | $bb sed -e 's/^\(.\).*$/\1/')" != "/" ]; then # it's a relative path, we need absolute here
			if [ -e $PWD/$scriptName ]; then
				jtPath=$PWD
			else # we couldn't find cpDep.sh in $PWD so we use the relative path after all
				jtPath=../$ownPath
			fi
		else
			jtPath=$ownPath
		fi

$bb cat > $pDir/update.sh << EOF
#! $sh

# This script contains all the dependencies copies and such and can be
# reran at any time to update what was copied to the jail.
ownPath=\$($bb dirname \$0)

# change this path to what you prefer
jailToolsPath=$jtPath

EOF
	fi

	echo "$bb sh \$jailToolsPath/scripts/$scriptName \$ownPath/root $destInJail $files" >> $pDir/update.sh
fi
