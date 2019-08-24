#! /bin/sh

case "$(readlink -f /proc/$$/exe)" in
	*dash)
		echo "We don't support dash"
		exit 1
	;;

	*)
		sh="$(readlink -f /proc/$$/exe)"
		echo "using shell : $sh"
	;;
esac

if [ $(($# < 3)) = 1 ]; then
	echo "Synopsis: $0 <chroot directory> <destination directory inside the jail> <file or directory> [files or directories]"
	echo "please input a destination chroot, a destination and files or directories to compute and copy"
	exit 1
fi

newStyleJail=0
destJail=$1
destInJail=$2
shift 2
files=$@

ownPath=$(dirname $0)

echo "$files -> $destJail/$destInJail"

if [ ! -e $destJail ]; then
	#echo "destination root does not exist, please create one first"
	#exit 1
	mkdir $destJail
fi

if [ -d $destJail/root ] && [ -d $destJail/run ] && [ -f $destJail/startRoot.sh ] && [ -f $destJail/rootCustomConfig.sh ]; then
	echo "New style jail directory detected"
	destJail=$destJail/root
	newStyleJail=1
else
	if [ ! -d $destJail/dev ] || [ ! -d $destJail/usr ] || [ ! -d $destJail/home ] || [ ! -d $destJail/etc ] || [ ! -d $destJail/bin ] || [ ! -d $destJail/sbin ] || [ ! -d $destJail/var ]; then
		echo "The directory '$destJail\` does not seem to be a valid jail filesystem, bailing out." 
		exit 1
	fi

	echo "Direct jail directory detected"
fi

createNewDir () {
	local distDir=$1

	local parent=$(dirname $distDir)
	if [ ! -d $distDir ]; then
		createNewDir $parent
		echo "$distDir -> directory $distDir doesn't exist"
		echo "$distDir -> creating directory $distDir"
		mkdir $distDir
	#else
		#echo "$distDir -> directory $parent exists"
	fi
}

safeCopyFile () {
	local src=$1
	local dstDir=$2
	local dstPath=$3
	#echo "src=$src dstDir=$dstDir dstPath=$dstPath"
	if [ -h $src ]; then # symbolic link check
		# this ensures that the file that the link points to is also copied
		link=$(readlink $src)
		if [ "$(dirname $link)" = "." ]; then
			link="$(dirname $src)/$link"
		fi
		if [ ! -e $link ]; then # in case the link is relative and not absolute
			link="$(dirname $src)/$link"
		fi
		#echo $src is a link to $link
		safeCopyFile "$link" "$dstDir" "$(dirname $link)"
	fi

	local dstPathCmp=$dstDir/$dstPath/$(basename $src)
	if 	[ ! -e $dstPathCmp ] || # if it just doesn't exist we copy it
		([ -e $dstPathCmp ] && [ ! -h $src ] && [ -h $dstPathCmp ]) ||  # this is in case our destination is actually a link, so we replace it with a real file
		([ -e $dstPathCmp ] && [ -h $src ] && [ ! -h $dstPathCmp ]) ||  # this is in case our destination is not a link, so we replace it with a link
		[ $dstPathCmp -ot $src ]; then # this is in case the destination does not exist or it is older than the origin
		createNewDir "$dstDir/$dstPath"
		echo "copying $src -> $dstPathCmp"
		cp -f --no-dereference --preserve="mode,timestamps" $src $dstPathCmp
	else # destination file already exists
		:
	fi
}

handle_files () {
	local finalDest=$1
	local file=$2

	#echo about to recurse those input values : $1
	for i in $file; do
		if [ ! -e $i ]; then
			echo "$i - No Such file or directory"
			continue
		fi
		#echo cycle $i
		if [ -d $i ]; then
			echo recursively handle the directory $i
			#echo "Next cycle destination : $finalDest/$(basename $i)"
			handle_files "$finalDest/$(basename $i)" "$(ls -d $i/*)"
			continue
		fi

		# the dependencies are copied first
		deps=$($sh $ownPath/compDeps.sh $i)
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

if [ "$newStyleJail" = "1" ]; then
	# parent
	pDir=$(dirname $destJail)
	scriptName=$(basename $0)

	if [ ! -e $pDir/update.sh ]; then
		jtPath=""

		if [ "${ownPath[1]:0:1}" != "/" ]; then # it's a relative path, we need absolute here
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

	echo "$sh \$jailToolsPath/$scriptName \$ownPath/root $destInJail $files" >> $pDir/update.sh
fi
