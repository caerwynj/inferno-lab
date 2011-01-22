#!/dis/sh

# Extract a tree from the hold as a .tar.gz file
# We can just take the data directory from the hold
# and put in place the tar data headers.

# can we do it any faster then doing a checkout and
# puttar of the directory.

# we can do it better by having a holdfs.

bind '#U' /n/local
cd /n/local

fs print  {filter  {and {not {match .svn}} {not {match -ar '(/appl/.*\.(dis|sbl))|(/sys.*\.*(obj|a|pdb))$'}}} {proto /lib/proto/full} } 
