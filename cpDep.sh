#! /bin/bash

if [ $(($# < 2)) == 1 ]; then
	echo "Synopsis: $0 [destination jail] [destination for file in jail] [file]"
	echo "please input a destination root and files to compute and copy"
	exit 1
fi

destJail=$1
destInJail=$2
shift 2
files=$@

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
	src=$1
	dstDir=$2
	dstPath=$3
	#echo "src=$src dstDir=$dstDir"
	if [ -h $src ]; then # symbolic link check
		link=`readlink $src`
		if [ "`dirname $link`" == "." ]; then
			link="`dirname $src`/$link"
		fi
		if [ ! -e $link ]; then # in case the link is relative and not absolute
			link="`dirname $src`/$link"
		fi
		#echo $src is a link to $link
		safeCopyFile "$link" "$dstDir" "$dstPath"
	fi
	# recursive calls to safeCopyFile change src and dstDir
	# so we assign them correct values
	src=$1
	dstDir=$2

	if [ -e ${dstDir}$src ] && [ ! -h $src ] && [ -h ${dstDir}$src ] || [ -e ${dstDir}$src ] && [ -h $src ] && [ ! -h ${dstDir}$src ] || [ ! -e ${dstDir}$src ]; then
		#echo about to copy $src to ${dstDir}/$src
		createNewDir2 "$dstDir/$dstPath"
		echo "copying $src -> $dstDir/$dstPath/`basename $src`"
		cp -f --no-dereference $src ${dstDir}/${dstPath}/`basename $src`
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
		deps=`bash compDeps.sh $i`
		for t in $deps; do
			#break;
			safeCopyFile "$t" "$destJail" "`dirname $t`"
		done

		# the actual directory or files are now copied
		#echo "Debug : $i -> $finalDest"
		safeCopyFile "$i" "$destJail" "$finalDest"
	done
}

handle_files "$destInJail" "$files"
