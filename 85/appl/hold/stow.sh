#!/dis/sh

load std string

hold=/n/hold

if {~ $#* 0} {
	echo usage: stow file.tar [root] >/fd/2
	exit
}
tar=$1
root=$2
n := `{date -n}
tmpf=0

if { ~ $tar  '*.tgz' } {
	nfile := `{basename $tar .tgz} ^ .tar
	gunzip < $tar > /tmp/ ^ $nfile
	tar = /tmp/ ^ $nfile
	tmpf=1
}

tarfs $tar /n/tar || raise fail:tarfs

name := `{basename $tar .tar}

if {~ $#root 0} {
	root = $name
}

if {ftest -e $hold/stowage/^$name} {
	echo stowage of same name already exists overwriting > /fd/2
}

install/updatelog -S -r /n/tar/ ^ $root /dev/null > $hold/stowage/$name


getlines {
	(sec seq v file sf mode uid gid mtime size sha) := ${split ' ' $line}
	if {! ~ $#sha 0} {
		(a b) := ${slice 0 2 $sha} ${slice 2 40 $sha}
		if {ftest -e $hold/objects/$a/$b} {} {
			echo a $file
			mkdir -p $hold/objects/$a
			gzip < /n/tar/$root/$file > $hold/objects/$a/$b
		}
	}
} < $hold/stowage/$name

sha := `{hold/putclump $hold/stowage/$name}

echo $n stow `{basename $tar} $sha >> $hold/logs/log
unmount /n/tar
if {~ $tmpf 1} {rm -f $tar}
