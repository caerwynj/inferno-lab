#!/dis/sh

branch := $1
hold:=/n/hold
current:=`{cat $hold/HEAD}

if {! ftest -e $hold/logs/$branch} {
	echo branch does not exist >/fd/2
	exit 1
}

hold/applylog -v -s $hold/logs/$current '#U' $hold  < $hold/logs/$branch
echo $branch > $hold/HEAD
