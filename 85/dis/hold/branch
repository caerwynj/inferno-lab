#!/dis/sh

name := $1
hold:=/n/hold
current:=`{cat $hold/HEAD}

cp $hold/logs/^ $current $hold/logs/^ $name
sha1=`{sha1sum < $hold/logs/^ $current}
echo  `{date -n} branch $current $name 0000000000000000000000000000000000000000 $sha1 >> $hold/logs/log
