#! /bin/sh

# this has to be called from the super script jailtools
if [ "$jailToolsPath" = "" ] || [ ! -d $jailToolsPath ]; then
	echo "This script has to be called from the 'jailtools' super script like so :"
	echo "jailtools upgrade <path to jail>"
	exit 1
fi

# if the result is 0 this means the files are the same
fileDiff() {
	diff -q $2/$1 $3/$1 >/dev/null
}

startUpgrade() {
	# we are already garanteed that the first argument is the jail path and it is valid
	local jPath=$1

	# convert the path of this script to an absolute path
	if [ "$jPath" = "." ]; then
		local jPath=$PWD
	else
		if [ "$(substring 0 1 $jPath)" = "/" ]; then
			# absolute path, we do nothing
			:
		else
			# relative path
			local jPath=$PWD/$jPath
		fi
	fi
	local jailName=$(basename $jPath)

	if [ ! -e $jPath/._rootCustomConfig.sh.initial ]; then
		echo "This jail is too old to be upgraded automatically, please upgrade it manually first"
		exit 1
	fi

	if [ -e $jPath/run/jail.pid ]; then
		echo "This jail may be running. You need to stop it before upgrading."
		exit 1
	fi

	if [ -e $jPath/startRoot.sh.orig ] || [ -e $jPath/rootCustomConfig.sh.orig ] || [ -e $jPath/rootCustomConfig.sh.patch ]; then
		echo "Either startRoot.sh.orig or rootCustomConfig.sh.orig or rootCustomConfig.sh.patch are present."
		echo "Please either remove them or move them somewhere else as we don't want to override them"
		echo "They could contain important backups from a previously failed upgrade attempt"
		echo "rerun this script once that is done"
		exit 1
	fi

	local njD=$jPath/.__jailUpgrade # the temporary new jail path
	[ ! -d $njD ] && mkdir $njD

	local nj=$njD/$jailName

	jailtools new $nj >/dev/null

	if $(fileDiff startRoot.sh $jPath $nj) && $(fileDiff ._rootCustomConfig.sh.initial $jPath $nj) ; then
		echo "Jail already at the latest version."
	else
		echo "Initial Checks complete. Upgrading jail."

		cp $jPath/rootCustomConfig.sh $jPath/rootCustomConfig.sh.orig
		cp $jPath/startRoot.sh $jPath/startRoot.sh.orig
		# first patch
		$jailToolsPath/busybox/busybox diff -p $jPath/._rootCustomConfig.sh.initial $jPath/rootCustomConfig.sh > $jPath/rootCustomConfig.sh.patch
		# second patch
		$jailToolsPath/busybox/busybox diff -p $nj/rootCustomConfig.sh $jPath/rootCustomConfig.sh > $jPath/rootCustomConfig.sh.patch2
		cp $nj/rootCustomConfig.sh $jPath
		cp $nj/startRoot.sh $jPath


		# we first make a patch from the initial
		# we then make a patch from the new jail to the current jail
		# these 2 patches are attempted in order, if one of them pass, we do it
		# otherwise, we have to rely on the user to patch manually

		# first attempt


		if cat $jPath/rootCustomConfig.sh.patch | $jailToolsPath/busybox/busybox patch; then
			cp $nj/._rootCustomConfig.sh.initial $jPath

			echo "Done upgrading jail. Thank you for using the jailUpgrade services."
		else 
			echo "There was an error upgrading your custom configuration file."
			echo "You will need to upgrade it manually and here are the steps :"
			echo "We moved the files of the upgrade in the path : $backupF"
			echo "You can check it out to determine what exactly went wrong."

			echo "First, take note that the file rootCustomConfig.sh now contains the default values. Don't worry."
			echo "Your changes to that file are in 2 locations."
			echo "We made a backup of your rootCustomConfig.sh to rootCustomConfig.sh.orig"
			echo "Also the file rootCustomConfig.sh.patch contains only your changes."
			echo "So use either of these to update the file rootCustomConfig.sh with your custom changes"
			echo "At that point, it should be safe to either remove or backup to some place all the .orig files and the patch"
			echo
			echo "If you don't want to upgrade manually right now, copy startRoot.sh.orig to startRoot.sh and rootCustomConfig.sh.orig to rootCustomConfig.sh"
			echo
			echo "We're sorry for the inconvenience. Thank you for using the jailUpgrade services."
		fi

		[ ! -d $jPath/.backup ] && mkdir $jPath/.backup
		local backupF=$jPath/.backup/$($jailToolsPath/busybox/busybox date +"%Y.%m.%d-%T")
		mkdir $backupF
		mv $jPath/rootCustomConfig.sh.orig $backupF
		mv $jPath/startRoot.sh.orig $backupF
		mv $jPath/rootCustomConfig.sh.patch $backupF
		mv $jPath/rootCustomConfig.sh.patch2 $backupF
		cp $jPath/._rootCustomConfig.sh.initial $backupF
	fi

	if [ "$njD" != "" ] && [ -d $nj ]; then
		rm -Rf $nj
		rmdir $njD
	fi
}
