#!/bin/sh
a=0
inp=$1
inp2=$2
tries=0

timI=$SECONDS
meth=0
RanT=0
out=""
tmpN=""


pro_ran()
{
	Ran1=$(($RANDOM / 10000))
	RanT=$Ran1
	if [ $(($RanT > 3)) ]; then
		Ran2=$(($RANDOM / 10000))
		Ran3=$(($RANDOM / 10000))
		RanT=$(($Ran1+$Ran2+$Ran3))
	fi
}

pro_ran2()
{
	while [ 0 != 1 ];
	do
		echo in
		tmpN=""
		pro_ran
		tmpN=$RanT
		echo "RanT_1 :$RanT"
		echo "tmpN_1 :$tmpN"
		pro_ran
		tmpN=$(($tmpN+$RanT))
		echo "RanT_2 :$RanT"
		echo "tmpN_2 :$tmpN"
		pro_ran
		tmpN=$(($tmpN+$RanT))
		echo "RanT_3 :$RanT"
		echo "tmpN_3 :$tmpN"	
		if [ $(($tmpN <= 25)) ]; then
			echo leaving...condition met
			RanT=$tmpN
			break
		fi
		echo "int :$tmpN "
	done
	echo "ext :$tmpN "
	tmpN=""
}

pro_ran3()
{
	while [ 0 != 1 ];
	do
		tmpN=""
		tmpN=$(($RANDOM / 1000))
		if [ $(($tmpN <= 25)) = 1 ]; then
			RanT=$tmpN
			break
		fi
	done
	
	#echo "gave $RanT"
	if [ $(($RanT > 25)) = 1 ]; then
		echo "error in script"
		exit
	fi
}

pro_let()
{
pro_ran3
case "$RanT" in
	0)
	if [ $meth = 0 ]; then
		out="a"
	else
		out="A"
	fi
	;;
	1)
	if [ $meth = 0 ]; then
		out="b"
	else
		out="B"
	fi
	;;
	2)
	if [ $meth = 0 ]; then
		out="c"
	else
		out="C"
	fi
	;;
	3)
	if [ $meth = 0 ]; then
		out="d"
	else
		out="D"
	fi
	;;
	4)
	if [ $meth = 0 ]; then
		out="e"
	else
		out="E"
	fi
	;;
	5)
	if [ $meth = 0 ]; then
		out="f"
	else
		out="F"
	fi
	;;
	6)
	if [ $meth = 0 ]; then
		out="g"
	else
		out="G"
	fi	
	;;
	7)
	if [ $meth = 0 ]; then
		out="h"
	else
		out="H"
	fi	
	;;
	8)
	if [ $meth = 0 ]; then
		out="i"
	else
		out="I"
	fi	
	;;
	9)
	if [ $meth = 0 ]; then
		out="j"
	else
		out="J"
	fi
	;;
	10)
	if [ $meth = 0 ]; then
		out="k"
	else
		out="K"
	fi	
	;;
	11)
	if [ $meth = 0 ]; then
		out="l"
	else
		out="L"
	fi	
	;;
	12)
	if [ $meth = 0 ]; then
		out="m"
	else
		out="M"
	fi	
	;;
	13)
	if [ $meth = 0 ]; then
		out="n"
	else
		out="N"
	fi	
	;;
	14)
	if [ $meth = 0 ]; then
		out="o"
	else
		out="O"
	fi	
	;;
	15)
	if [ $meth = 0 ]; then
		out="p"
	else
		out="P"
	fi	
	;;
	16)
	if [ $meth = 0 ]; then
		out="q"
	else
		out="Q"
	fi	
	;;
	17)
	if [ $meth = 0 ]; then
		out="r"
	else
		out="R"
	fi	
	;;
	18)
	if [ $meth = 0 ]; then
		out="s"
	else
		out="S"
	fi	
	;;
	19)
	if [ $meth = 0 ]; then
		out="t"
	else
		out="T"
	fi	
	;;
	20)
	if [ $meth = 0 ]; then
		out="u"
	else
		out="U"
	fi
	;;
	21)
	if [ $meth = 0 ]; then
		out="v"
	else
		out="V"
	fi	
	;;
	22)
	if [ $meth = 0 ]; then
		out="w"
	else
		out="W"
	fi	
	;;
	23)
	if [ $meth = 0 ]; then
		out="x"
	else
		out="X"
	fi
	;;
	24)
	if [ $meth = 0 ]; then
		out="y"
	else
		out="Y"
	fi	
	;;
	25)
	if [ $meth = 0 ]; then
		out="z"
	else
		out="Z"
	fi	
	;;
	*)
	echo "fatal error exiting error #$RanT"
	exit
	;;
esac
}

testing()
{
while [ $a != 1 ];
	do
	pro_ran
	#tem=$(($RANDOM / 10000))
	tem=$RanT
	verif=0
	echo $tem
	if [ $tem = $verif ]; then
		a=$(($a+1))
	fi
	tries=$(($tries+1))
done
echo "took exactly $(($SECONDS - $timI)) seconds to do and $(($tries+1)) tries"
}

proba()
{
pour=0
a_0=0
a_1=0
a_2=0
a_3=0
a_4=0
a_5=0
a_6=0
a_7=0
a_8=0
a_9=0
while [ $SECONDS != $(($timI+60)) ];
do
	pro_ran
	tem2=$RanT
	case $tem2 in
		0)
			a_0=$(($a_0+1));;
		1)
			a_1=$(($a_1+1));;
		2)
			a_2=$(($a_2+1));;
		3)
			a_3=$(($a_3+1));;
		4)
			a_4=$(($a_4+1));;
		5)
			a_5=$(($a_5+1));;
		6)
			a_6=$(($a_6+1));;
		7)
			a_7=$(($a_7+1));;
		8)
			a_8=$(($a_8+1));;
		9)
			a_9=$(($a_9+1));;
	esac
	if [ $pour != $((($SECONDS*100)/($timI+60))) ]; then
		pour=$((($SECONDS*100)/($timI+60)))
		printf "-"
	fi
done
echo "done...probability of : 0:$a_0, 1:$a_1, 2:$a_2, 3:$a_3, 4:$a_4, 5:$a_5, 6:$a_6, 7:$a_7, 8:$a_8, 9:$a_9"
tot=$(($a_0+$a_1+$a_2+$a_3+$a_4+$a_5+$a_6+$a_7+$a_8+$a_9))
b_0=$((($a_0*100)/$tot))
b_1=$((($a_1*100)/$tot))
b_2=$((($a_2*100)/$tot))
b_3=$((($a_3*100)/$tot))
b_4=$((($a_4*100)/$tot))
b_5=$((($a_5*100)/$tot))
b_6=$((($a_6*100)/$tot))
b_7=$((($a_7*100)/$tot))
b_8=$((($a_8*100)/$tot))
b_9=$((($a_9*100)/$tot))


echo "for 0:$b_0%, 1:$b_1%, 2:$b_2%, 3:$b_3%, 4:$b_4%, 5:$b_5%, 6:$b_6%, 7:$b_7%, 8:$b_8%, 9:$b_9%"
}

main()
{
t=0
password=""


while [ $t != $Plen ];
do
	R=$(($RANDOM / 10000))
	if [ $R = 0 ];then
		meth=0
		pro_let
		password=${password}$out	
	fi
	if [ $R = 1 ];then
		meth=1
		pro_let
		password=${password}$out
	fi
	if [ $R = 2 ];then
		pro_ran
		password=${password}$RanT
	fi
	if [ $R = 3 ];then
		pro_ran
		password=${password}$RanT
	fi
	t=$(($t+1))
done
}


case "$inp" in
	"--help")
		echo "   syntax : gene -f <password digits>"
		echo "   -f is to only show the password"
	;;
	"-f")
		Plen=8
		if [[ $inp2 != "" ]]; then
			Plen=$inp2
		fi
		main
		echo $password
	;;
	*)
		Plen=8
		if [[ $inp != "" ]]; then
			Plen=$inp
		fi
		main
		echo "	generating a random password of $Plen digits"
		echo	
		echo $password
		echo
		echo "	took $(($SECONDS-$timI)) seconds to generate this password"
	;;
esac
