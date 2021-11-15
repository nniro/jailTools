bb="$BB"
shower="$JT_SHOWER"
runner="$JT_RUNNER"

#echo "BB : '$bb' -- shower : '$shower' -- runner : '$runner'"
#echo "inputs : \"$@\""

OPTIND=0
outputBit="false"
outputLinkingType="false"
outputInterpreter="false"
outputDeps="false"
while getopts ablid f ; do
	case $f in
		a) outputBits="true"; outputLinkingType="true"; outputInterpreter="true"; outputDeps="true";;
		b) outputBits="true";;
		l) outputLinkingType="true";;
		i) outputInterpreter="true";;
		d) outputDeps="true";;
	esac
done || exit 1
[ $(($OPTIND > 1)) = 1 ] && shift $($bb expr $OPTIND - 1)

outputHelp() {
	echo "Gather ELF information on a file or library."
	echo "Synopsis -[blida] file"
	echo ""
	echo " -b		Output if the executable is 32 or 64bit."
	echo " -l		Output Linking type."
	echo " -i		Output interpreter (only if dynamically linked)."
	echo " -d		Output shared object dependencies (only if dynamically linked)."
	echo " -a		Output all informations."
}

if [ "$1" = "" ]; then
	echo "Please provide a file from which to gather information"
	outputHelp
	exit 1
else
	iFile=$1

	if [ ! -e $iFile ]; then
		echo "No such file or directory \`$iFile'"
		outputHelp
		exit 1
	else
		iFile=$($bb realpath $iFile)
	fi
fi

getBytes() {
	file=$1
	offset=$2
	size=$3
	$bb xxd -c $size -s $offset -p $file -l $size
}

# check the ELF magic
if getBytes $iFile 0 4 | $bb grep -q "^7f454c46"; then
	:
else
	echo "File is not an executable or dynamic library"
	outputHelp
	exit 1
fi

# convert little endian to big endian
convLE() {
	$bb awk '
	{
		total = split($0, raw, "")

		rTotal = total / 2
		if (rTotal == 1) {
			print raw[1] raw[2]
		} else if (rTotal == 2) {
			print raw[3] raw[4] raw[1] raw[2]
		} else if (rTotal == 4) {
			print raw[7] raw[8] raw[5] raw[6] raw[3] raw[4] raw[1] raw[2]
		} else if (rTotal == 8) {
			print raw[15] raw[16] raw[13] raw[14] raw[11] raw[12] raw[9] raw[10] raw[7] raw[8] raw[5] raw[6] raw[3] raw[4] raw[1] raw[2]
		} else { # no conversion in that case
			print $0
		}
	}'
}

#printf "%d\n" "0x$(echo 0900 | convLE)"
#printf "%d\n" "0x$(echo 09000000 | convLE)"

#exit 0

fType=$(getBytes $iFile 0x10 2)
endianness=$(getBytes $iFile 0x05 1) # 1 is little, 2 is big endian
bitSize=$(getBytes $iFile 0x04 1) # 1 is 32bit, 2 is 64bit

if [ "$outputBits" = "true" ]; then
	if [ "$bitSize" = "02" ]; then # 64 bit
		echo "64bit"
	elif [ "$bitSize" = "01" ]; then # 32 bit
		echo "32bit"
	fi
fi

getBytesBiased() { # takes into account the bitsize
	file=$1
	offset32=$2
	offset64=$3
	size=$4
	[ "$bitSize" = "01" ] && offset=$offset32 || offset=$offset64
	result=$(getBytes $file $offset $size)
	# deal with the endianness
	if [ $(($size < 2)) = 1 ] ; then # no need to deal with endianness on 1 byte
		echo $result
	elif [ $(($size <= 8)) = 1 ]; then
		if [ "$endianness" = "02" ]; then # big endian is as is
			echo $result
		else # little endian is the troublemaker
			echo $result | convLE
		fi
	else
		echo $result
	fi
}

toInt() {
	printf "%d" "0x$($bb cat)"
}

case $fType in
	"0200")
		:
	;;
	"0300")
		:
	;;

	*)
		echo "Unhandled file type"
		exit 1
	;;
esac

programHOffset=$(getBytesBiased $iFile 0x1c 0x20 4 | toInt)
programHEntries=$(getBytesBiased $iFile 0x2c 0x38 2 | toInt)

#echo "program header offset : $programHOffset"
#echo "program header entries : $programHEntries"

isDynamic=false
interpreter=""

[ "$bitSize" = "01" ] && entryOffset="0x20" || entryOffset="0x38"
for i in $($bb seq 0 $programHEntries); do
	offset=$(($programHOffset + (i * entryOffset)))
	#echo "offset[$i] : $offset"
	peType=$(getBytesBiased $iFile $offset $offset 4 | toInt)
	#echo "$peType"
	#getBytesBiased $iFile $offset $offset $(printf "%d" $entryOffset) | xxd
	if [ "$peType" = "2" ]; then # dynamic
		isDynamic=true
	fi
	if [ "$peType" = "3" ]; then
		if [ "$bitSize" = "01" ]; then # 32bit
			eOffset=$(getBytes $iFile $(($offset + 0x04)) 4 | convLE | toInt)
			eSize=$(getBytes $iFile $(($offset + 0x10)) 4 | convLE | toInt)
		else # 64bit
			eOffset=$(getBytes $iFile $(($offset + 0x08)) 8 | convLE | toInt)
			eSize=$(getBytes $iFile $(($offset + 0x20)) 8 | convLE | toInt)
		fi

		interpreter=$(getBytes $iFile $eOffset $eSize | $bb awk '
		{
			total = split($0, r, "")
			for (i = 1; i <= total; i+=2) {
				printf "%c", int("0x" r[i] r[i + 1])
			}
		}')
	fi
	#echo $i
done

if [ "$isDynamic" = "true" ]; then
	[ "$outputLinkingType" = "true" ] && echo "Dynamically linked"
	[ "$outputInterpreter" = "true" ] && echo "interpreter : $interpreter"
	if [ "$outputDeps" = "true" ]; then
		[ -e $interpreter ] && $interpreter --list $iFile
	fi
else
	[ "$outputLinkingType" = "true" ] && echo "Statically linked"
fi
