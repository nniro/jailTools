#! /bin/sh

if [ "$1" != "" ]; then
	if [ ! -d $1 ]; then
		echo "Please ensure the path is a directory and is writable"
		exit 1
	else
		scriptsDir=$(dirname $0)

		if [ "${scriptsDir:0:1}" != "/" ]; then # if the directory is not an absolute path, we use PWD
			scriptsDir=$PWD
		fi

		# we change the internal path to the path where this script is
		cat $scriptsDir/jailtools | sed -e "s@jailToolsPath=ScriptPath@jailToolsPath=$scriptsDir@" > $1/jailtools
		ln -sfT $1/jailtools $1/jtools
		ln -sfT $1/jailtools $1/jt
		chmod u+x,g+x $scriptsDir/jailtools
		echo "Done. You may have to do : chmod +x $scriptsDir/jailtools  to run it seemlessly"
	fi
else
	echo "Please input a directory where you want to install the \`jailtools' master script"
	echo "Note that only that script is installed (along with the \`jt' and \`jtools' symlinks). It finds the other scripts by reference."
	exit 1
fi
