#! /bin/sh

bb="$BB"
shower="$JT_SHOWER"
runner="$JT_RUNNER"

configFile=rootCustomConfig.sh

filesUpgrade=$(cat << EOF
._rootCustomConfig.sh.initial
rootDefaultConfig.sh
jailLib.sh
startRoot.sh
EOF
)

startUpgrade() {
	# we are already garanteed that the first argument is the jail path and it is valid
	local jPath=$1
	shift

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

	local njD=$jPath/.__jailUpgrade # the temporary new jail path
	local jailName=$(basename $jPath)
	local nj=$njD/$jailName # new jail

	case $1 in
		--continue)

			if [ ! -e $jPath/$configFile.merged ]; then
				echo "This command is to continue a failed automatic upgrade session."
				echo "It is not currently the case, bailing out."
				exit 1
			fi

			mv $jPath/$configFile.merged $jPath/$configFile
			[ -e $jPath/$configFile.patch ] && rm $jPath/$configFile.patch
			[ -e $jPath/$configFile.new ] && rm $jPath/$configFile.new
			for file in $filesUpgrade; do
				[ -e $jPath/$file.new ] && mv $jPath/$file.new $file
			done

			[ -d $nj ] && rm -Rf $nj

			echo "Done upgrading jail. Thank you for using the jailUpgrade service."
			exit 0
		;;

		--abort)
			[ -e $jPath/$configFile.new ] && rm $jPath/$configFile.new
			[ -e $jPath/$configFile.patch ] && rm $jPath/$configFile.patch
			for file in $filesUpgrade; do
				[ -e $jPath/$file.new ] && rm $jPath/$file.new
			done

			[ -d $nj ] && rm -Rf $nj

			echo "Reverted changes done by the upgrade. Thank you for using the jailUpgrade service."
			exit 0
		;;

		"")
		;;

		*)
			echo "upgrade: invalid command \`$1'"
			exit 1
		;;
	esac

	# if the result is 0 this means the files are the same
	fileDiff() {
		$bb diff -q $2/$1 $3/$1 >/dev/null 2>/dev/null
		return $?
	}

	if [ ! -e $jPath/._$configFile.initial ]; then
		echo "This jail is too old to be upgraded automatically, please upgrade it manually first"
		exit 1
	fi

	if [ -e $jPath/run/jail.pid ]; then
		echo "This jail may be running. You need to stop it before upgrading."
		exit 1
	fi

	for file in $filesUpgrade; do
		if [ -e $jPath/$file.new ]; then
			echo "There is an already started upgrade attempt going. Please finish with that one first."
			echo
			echo "either do	: jt upgrade --continue"
			echo "or 	: jt upgrade --abort"
			echo
			exit 1
		fi
	done

	[ ! -d $njD ] && mkdir $njD


	jailtools new $nj >/dev/null 2>/dev/null

	isChanged="false"
	for file in $filesUpgrade; do
		if [ -e $file ]; then
			fileDiff $file $jPath $nj
			if ! fileDiff $file $jPath $nj; then
				isChanged="true"
				break
			fi
		else # the file doesn't exist
			isChanged="true"
			break
		fi
	done

	if [ "$isChanged" = "false" ]; then
		echo "Jail already at the latest version."
	else
		echo "Initial Checks complete. Upgrading jail."

		$bb diff -p $jPath/._$configFile.initial $jPath/$configFile > $jPath/$configFile.patch

		cp $nj/$configFile $jPath/$configFile.new
		for file in $filesUpgrade; do
			cp $nj/$file $jPath/$file.new
		done

		[ ! -d $jPath/.backup ] && mkdir $jPath/.backup
		local backupF=$jPath/.backup/$($bb date +"%Y.%m.%d-%T")
		mkdir $backupF

		cp $jPath/$configFile $backupF
		cp $jPath/$configFile.patch $backupF
		for file in $filesUpgrade; do
			cp $jPath/$file $backupF
		done

		# we apply the patch to the new configuration file
		if cat $jPath/$configFile.patch | $bb patch $jPath/$configFile.new; then
			mv $jPath/$configFile.new $jPath/$configFile
			for file in $filesUpgrade; do
				mv $jPath/$file.new $jPath/$file
			done
			rm $jPath/$configFile.patch

			echo "Done upgrading jail. Thank you for using the jailUpgrade service."
		else 
			echo
			echo "*******************************************************************"
			echo
			echo "There was an error upgrading your custom configuration file."
			echo
			echo
			echo "You will need to upgrade it manually. Here's a few suggestions on how to do that :"
			echo "	NOTE : do your changes in the file $configFile.merged"
			echo
			echo " 1- You could attempt to upgrade manually by comparing your $configFile.merged with $configFile.new and merge the changes yourself."
			echo
			echo " 2- you can check the backup path to determine what exactly went wrong."
			echo
			echo " 3- you can use a tool like GNU diff3 to handle the changes for you. like so :"
			echo
			echo "	diff3 -m $configFile.new ._$configFile.initial $configFile > $configFile.merged"
			echo
			echo
			echo "When you are done merging $configFile.merged just do :"
			echo
			echo "	jt upgrade --continue"
			echo
			echo
			echo "You can abort this upgrade by doing :"
			echo
			echo "	jt upgrade --abort"
			echo
			echo "This will put everything back to what it was before."
			echo
			echo "We're sorry for the inconvenience. Thank you for using the jailUpgrade service."

			cp $jPath/$configFile.new $jPath/$configFile.merged
		fi
	fi

	if [ "$njD" != "" ] && [ -d $nj ]; then
		rm -Rf $nj
		rmdir $njD
	fi
}
