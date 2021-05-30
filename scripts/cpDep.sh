#! /bin/sh

case "$(readlink -f /proc/$$/exe)" in
	*zsh)
		setopt shwordsplit
		sh="$(readlink -f /proc/$$/exe)"
	;;

	*busybox)
		sh="$(readlink -f /proc/$$/exe) sh"
	;;

	*)
		sh="$(readlink -f /proc/$$/exe)"
	;;
esac

if [ $(($# < 3)) = 1 ]; then
	echo "Synopsis: $0 <chroot directory> <destination directory inside the jail> <file or directory> [files or directories]"
	echo "please input a destination chroot, a destination and files or directories to compute and copy"
	exit 1
fi

isJail=0
destJail=$1
destInJail=$2
debugging=0
shift 2
files=$@

ownPath=$(dirname $0)

[ "$debugging" = "1" ] && echo "$files -> $destJail/$destInJail"

if [ ! -e $destJail ]; then
	#echo "destination root does not exist, please create one first"
	#exit 1
	mkdir $destJail
fi

if [ -d $destJail/root ] && [ -d $destJail/run ] && [ -f $destJail/startRoot.sh ] && [ -f $destJail/rootCustomConfig.sh ]; then
	isJail=1
	destJail=$destJail/root
fi

createNewDir () {
	local distDir=$1

	local parent=$(dirname $distDir)
	if [ ! -d $distDir ]; then
		createNewDir $parent
		[ "$debugging" = "1" ] && echo "$distDir -> directory $distDir doesn't exist"
		[ "$debugging" = "1" ] && echo "$distDir -> creating directory $distDir"
		if [ "$debugging" = "1" ]; then
			mkdir $distDir
		else
			mkdir $distDir 2>/dev/null
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
		link=$(readlink $src)
		if [ "$(dirname $link)" = "." ]; then
			link="$(dirname $src)/$link"
		fi
		if [ ! -e $link ]; then # in case the link is relative and not absolute
			link="$(dirname $src)/$link"
		fi
		[ "$debugging" = "1" ] && echo $src is a link to $link
		safeCopyFile "$link" "$dstDir" "$(dirname $link)"
		[ "$debugging" = "1" ] && echo "done copying link"
	fi

	local dstPathCmp=$dstDir/$dstPath/$(basename $src)
	if 	[ ! -e $dstPathCmp ] || # if it just doesn't exist we copy it
		([ -e $dstPathCmp ] && [ ! -h $src ] && [ -h $dstPathCmp ]) ||  # this is in case our destination is actually a link, so we replace it with a real file
		([ -e $dstPathCmp ] && [ -h $src ] && [ ! -h $dstPathCmp ]) ||  # this is in case our destination is not a link, so we replace it with a link
		[ $dstPathCmp -ot $src ]; then # this is in case the destination does not exist or it is older than the origin
		createNewDir "$dstDir/$dstPath"
		[ "$debugging" = "1" ] && echo "copying $src -> $dstPathCmp"
		cp -f --no-dereference --preserve="mode,timestamps" $src $dstPathCmp
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

	rawOutput=$(ldd $file 2> /dev/null)
	#rawOutput=$(echo -e $example)

	# handle statically linked files
	if [ "`echo -e $rawOutput | sed -e "s/.*\(statically\|not a dynamic\).*/static/; {t toDelAll} " -e ":toDelAll {p; b delAll}; :delAll {d; b delAll}"`" = "static" ]; then
		# we exit returning nothing for statically linked files
		exit 0
	fi

	echo -e "$rawOutput" | sed -e "s/^\(\|[ \t]*\)\([^ ]*\) (.*)$/\2/" -e "s/[^ ]* \=> \([^ ]*\) (.*)$/\1/" | sed -e "/.*linux-gate.*/ d"
}

handle_files () {
	local finalDest=$1

	#echo about to recurse those input values : $1
	for i in $(echo "$2"); do
		if [ ! -e $i ]; then
			[ "$debugging" = "1" ] && echo "$i - No Such file or directory"
			continue
		fi
		#echo cycle $i
		if [ -d $i ]; then
			[ "$debugging" = "1" ] && echo recursively handle the directory $i
			#echo "Next cycle destination : $finalDest/$(basename $i)"
			handle_files "$finalDest/$(basename $i)" "$(ls -d $i/*)"
			continue
		fi

		# the dependencies are copied first
		deps=$(compDeps $i)
		for t in $deps; do
			#break;
			if [ -e $t ]; then
				safeCopyFile "$t" "$destJail" "$(dirname $t)"
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
	pDir=$(dirname $destJail)
	scriptName=$(basename $0)

	if [ ! -e $pDir/update.sh ]; then
		jtPath=""

		if [ "$(echo $ownPath | sed -e 's/^\(.\).*$/\1/')" != "/" ]; then # it's a relative path, we need absolute here
			if [ -e $PWD/$scriptName ]; then
				jtPath=$PWD
			else # we couldn't find cpDep.sh in $PWD so we use the relative path after all
				jtPath=../$ownPath
			fi
		else
			jtPath=$ownPath
		fi

cat > $pDir/update.sh << EOF
#! $sh

# This script contains all the dependencies copies and such and can be
# reran at any time to update what was copied to the jail.
ownPath=\$(dirname \$0)

# change this path to what you prefer
jailToolsPath=$jtPath

EOF
	fi

	echo "$sh \$jailToolsPath/scripts/$scriptName \$ownPath/root $destInJail $files" >> $pDir/update.sh
fi
