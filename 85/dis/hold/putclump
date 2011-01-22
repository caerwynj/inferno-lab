#!/dis/sh
load expr arg string

args := $*
hold := /n/hold
(arg
	d+ {hold = $arg}
	'*' {echo unknown option $opt}
	- $args
)
if {~ $#* 0} {
	echo usage: putclump file > /fd/2
	exit
}

for i in $* {
	file := $i
	
	(sha f) := `{sha1sum $file}
	(a b) := ${slice 0 2 $sha} ${slice 2 40 $sha}
	
	if {ftest -e $hold/objects/$a/$b} {} {
		mkdir -p $hold/objects/$a
		gzip < $file > $hold/objects/$a/$b
	}
#	echo $hold/$a/$b
	echo $sha
}
