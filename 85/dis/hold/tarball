#!/dis/sh

if {! ~ $#* 1} {echo usage: tarball root; raise arg}

root=$1

bind '#U' /n/^$root
cd /n

fs print '{filter  {and {not {match .svn}} {not {match -ar ''(/appl/.*\.(dis|sbl))|(/sys.*\.*(o|obj|a|pdb|map|exe))$''}}} {proto -r '^$root^' /lib/proto/tarball} }' | puttar 
