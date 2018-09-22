#! /bin/sh

if [ $(($# < 3)) = 1 ]; then
	echo "Synopsis: $0 <chroot directory> <destination directory inside the jail> <file or directory> [files or directories]"
	echo "please input a destination chroot, a destination and files or directories to compute and copy"
	exit 1
fi

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

createNewDir () {
	local src=$1
	local distDir=$2

	local dir=`dirname $src`
	if [ ! -d $distDir/$dir ]; then
		#echo "$distDir -> directory $dir exist"
	#else
		echo "$distDir -> directory $dir doesn't exist"
		createNewDir $dir $distDir
		echo "$distDir -> creating directory $dir"
		mkdir $distDir/$dir
	fi
}

createNewDir2 () {
	local distDir=$1

	local parent=`dirname $distDir`
	if [ ! -d $distDir ]; then
		createNewDir2 $parent
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
	#echo "src=$src dstDir=$dstDir"
	if [ -h $src ]; then # symbolic link check
		# this ensures that the file that the link points to is also copied
		link=`readlink $src`
		if [ "`dirname $link`" = "." ]; then
			link="`dirname $src`/$link"
		fi
		if [ ! -e $link ]; then # in case the link is relative and not absolute
			link="`dirname $src`/$link"
		fi
		#echo $src is a link to $link
		safeCopyFile "$link" "$dstDir" "`dirname $link`"
	fi

	local dstPathCmp=$dstDir/$dstPath/`basename $src`
	#printf "$dstPathCmp is older than $src : "; [ $dstPathCmp -ot $src ] && echo yes || echo no

	if 	([ -e $dstPathCmp ] && [ ! -h $src ] && [ -h $dstPathCmp ]) ||  # this is in case our destination is actually a link, so we replace it with a real file
		([ -e $dstPathCmp ] && [ -h $src ] && [ ! -h $dstPathCmp ]) ||  # this is in case our destination is not a link, so we replace it with a link
		[ $dstPathCmp -ot $src ]; then # this is in case the destination does not exist or it is older than the origin
		#echo about to copy $src to ${dstDir}/$src
		createNewDir2 "$dstDir/$dstPath"
		echo "copying $src -> $dstPathCmp"
		cp -f --no-dereference --preserve="mode,timestamps" $src $dstPathCmp
	else
		#echo destination file already exists
		return
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
			#if [ ! -d ${destJail}$i ]; then
				#mkdir ${destJail}$i
			#fi
			#echo "Next cycle destination : $finalDest/`basename $i`"
			handle_files "$finalDest/`basename $i`" "`ls -d $i/*`"
			continue
		fi

		# the dependencies are copied first
		deps=`sh $ownPath/compDeps.sh $i`
		for t in $deps; do
			#break;
			if [ -e $t ]; then
				safeCopyFile "$t" "$destJail" "`dirname $t`"
			fi
		done

		# the actual directory or files are now copied
		#echo "Debug : $i -> $finalDest"
		safeCopyFile "$i" "$destJail" "$finalDest"
	done
}

handle_files "$destInJail" "$files"
