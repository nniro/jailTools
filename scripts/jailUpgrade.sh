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
	# we are already garanteed that the first argument is the absolute jail path and it is valid
	local jPath=$1
	shift

	local njD=$jPath/.__jailUpgrade # the temporary new jail path
	local jailName=$(basename $jPath)
	local nj=$njD/$jailName # new jail

	local result=""
	result=$(callGetopt "upgrade [OPTIONS]" \
		-o '' 'continue' 'continue an upgrade process' 'doContinue' 'false' \
		-o '' 'abort' 'abort the current upgrade process' 'doAbort' 'false' \
		-- "$@")
	local err="$?"

	if [ "$err" = "0" ]; then
		if getVarVal 'doContinue' "$result" >/dev/null; then
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
		elif getVarVal 'doAbort' "$result" >/dev/null; then
			[ -e $jPath/$configFile.new ] && rm $jPath/$configFile.new
			[ -e $jPath/$configFile.patch ] && rm $jPath/$configFile.patch
			for file in $filesUpgrade; do
				[ -e $jPath/$file.new ] && rm $jPath/$file.new
			done

			[ -d $nj ] && rm -Rf $nj

			echo "Reverted changes done by the upgrade. Thank you for using the jailUpgrade service."
			exit 0
		fi
	else
		exit 1
	fi

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


	$JT_CALLER new $nj >/dev/null 2>/dev/null

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

		# TODO do a check if the embedded busybox jt is of the same version as 'jt' beind used.

		# we apply the patch to the new configuration file
		if cat $jPath/$configFile.patch | $bb patch $jPath/$configFile.new; then
			mv $jPath/$configFile.new $jPath/$configFile
			for file in $filesUpgrade; do
				mv $jPath/$file.new $jPath/$file
			done
			rm $jPath/$configFile.patch

			echo "Done upgrading jail. Thank you for using the jailUpgrade service."
		else 
			diff3Path=$($bb which diff3)
			if [ "$diff3Path" != "" ]; then
				$diff3Path -m $configFile.new ._$configFile.initial $configFile > $configFile.merged
cat - << EOF
*******************************************************************

There was an error upgrading your custom configuration file.

You will need to upgrade it manually.
NOTE : do your changes in the file $configFile.merged

We took the liberty to use the command diff3 and output it's result to $configFile.merged.


Before continuing, fire up a text editor and open up $configFile.merged and check for visual
merge cues and fix them.


When you are done merging $configFile.merged just do :

	jt upgrade --continue

You can abort this upgrade by doing :

	jt upgrade --abort

This will put everything back to how it was before.

We're sorry for the inconvenience. Thank you for using the jailUpgrade service.
EOF
			else
cat - << EOF
*******************************************************************

There was an error upgrading your custom configuration file.

You will need to upgrade it manually. Here's a few suggestions on how to do that :
NOTE : do your changes in the file $configFile.merged

1- You could attempt to upgrade manually by comparing your $configFile.merged with $configFile.new and merge the changes yourself.
2- you can check the backup path to determine what exactly went wrong.
3- you can use a tool like GNU diff3 to handle the changes for you. like so :

	diff3 -m $configFile.new ._$configFile.initial $configFile > $configFile.merged

When you are done merging $configFile.merged just do :

	jt upgrade --continue

You can abort this upgrade by doing :

	jt upgrade --abort

This will put everything back to how it was before.

We're sorry for the inconvenience. Thank you for using the jailUpgrade service.
EOF

				cp $jPath/$configFile.new $jPath/$configFile.merged
			fi
		fi
	fi

	if [ "$njD" != "" ] && [ -d $nj ]; then
		rm -Rf $nj
		rmdir $njD
	fi
}
