#!/dis/sh

load std string

hold=/n/hold
branch = `{cat $hold^/HEAD}
log = $hold^/logs/^ $branch
n := `{date -n}
tmp := /tmp/stow. ^ ${pid}

#TODO needs to create a brand new log each time.

install/updatelog -S -r '#U'  -x tmp -x mail $log -p /lib/proto/full > $tmp

parent = `{sha1sum < $log}
cat $tmp >> $log


getlines {
	(sec seq v file sf mode uid gid mtime size sha rest) := ${split ' ' $line}
	if {! ~ $#sha 0} {
#		$sha = ${hd $sha}
		(a b) := ${slice 0 2 $sha} ${slice 2 40 $sha}
		if {ftest -e $hold/objects/$a/$b} {} {
			echo a $file
			mkdir -p $hold/objects/$a
			gzip < '#U/' ^ $file > $hold/objects/$a/$b
		}
	}
} < $tmp

lsha := `{hold/putclump $log}
echo $n commit $branch $parent $lsha >> $hold/logs/log
rm $tmp

