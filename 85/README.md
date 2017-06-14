# NAME
lab 85 - stowage

# NOTES
In an earlier post I defined a venti-lite based on two shell scripts, getclump and putclump, that stored files in a content addressed repository, which in that instance was just an append-only gzip tar archive with an index.

After learning a little about the git SCM, this lab re-writes those scripts to use a repository layout more like git's. The key thing to know about the git repository is that it uses sha1sum(1) content addressing and that it stores the objects as regular files in a filesystem using the hash as the directory and filename,

	objects/hh/hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh
	
In the objects directory is 256 directories named for every 2 character prefix of the sha1hash of the object. The filename is the remaining 38 characters of the hash.

Putclump calculates the hash, slices it to make the prefix and filename, tests if the file already exists, and if not writes the compressed data to the new file. Here is the important part of putclump,

	 (sha f) := `{sha1sum $file}
	 (a b) := ${slice 0 2 $sha} ${slice 2 40 $sha}
	 
	 if {ftest -e $hold/objects/$a/$b} {} {
	  mkdir -p $hold/objects/$a
	  gzip < $file > $hold/objects/$a/$b
	 }


Getclump just needs to look up the file given a hash

	 sha := $1
	 (a b) := ${slice 0 2 $sha} ${slice 2 40 $sha}
	 files := `{ls $hold/objects/$a/$b^* >[2] /dev/null}
	 if {~ $#files 1} {gunzip < $files } 

Because the git repository uses a regular file system to store objects, it makes it considerably easier to work with than the compacted file system like tar.gz, or an application specific binary format like venti. This is because instead of having to create new tools to read and write binary formats, we can re-use existing tools, like sh(1), tarfs(4), updatelog(8), and applylog(8).

For example, I wrote a script, stow, that takes a tarball and stores it in my repository, called the hold. The hold should be created first with the following directories,

	 /n/hold/logs
	 /n/hold/objects
	 /n/hold/stowage

Then give stow the name of a .tar or .tgz file. Files not found in the hold and that were added are printed to stdout.

 	% stow acme-0.11.tgz
	 ...
	 %

Stow uses updatelog(8) to create a stowage manifest file for the tarball I added. This manifest is saved under /n/stowage. The manifest records the pathname, perms, and sha1 hash of every file in the tarball.

Now that I've stowed all my tarballs I need a way of getting things out.

I built a holdfs, derived from tarfs(4), to read the stowage manifest and present files from the hold. By default the file system is mounted on /mnt/arch.

	% holdfs /n/hold/stowage/acme-0.11

The hold with its stowage is be a step up from a directory tarpit of tarballs. I can accumulate a version history based on tar.gz releases like that for acme-sac and inferno. The vitanuova downloads site contains inferno history going back to 1997. My downloads page contains snapshots of inferno from 2002 to 2006 and acme-sac after that.

My intended application for this was that I could encourage forks of a project and merge back many individuals releases into a single repository and still do useful comparisons.

Using a filled hold I should be able to do analysis of a file history based on the stowage manifests. Contained in this lab are a few experimental scripts to build out more of an SCM. For example, the script hold/diff attempts to use updatelog to compare a manifest with the current tree. And hold/difflog uses a modified applylog(8) to compare two manifests.

The nautical references suggest a distributed and loosely coupled network like that of shipping, and is also influenced by git's design. The unit of transfer is a tarball. It is stowed into the ships hold, along with the manifest. A file system interprets the manifests and gives an interface for searching the hold. There is also keep a ships log of what was stowed and when. I can extract patches, files, tarballs, or the complete stowage in my hold to share with someone else.

This is a simple system:

	     28 putclump.sh
	     16 getclump.sh
	     54 stow.sh
	    669 holdfs.b
	    767 total

But then most of what was needed already existed in inferno.