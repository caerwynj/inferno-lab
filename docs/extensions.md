
## Extensions
* 92 vxinferno

### lab 92 - vxinferno

In this lab I create a new Inferno builtin module that calls the <a href="http://pdos.csail.mit.edu/~baford/vm/">vx32</a> 
library and get a minimal system working
that runs native x86 code, with system calls redirected to inferno's system calls
and therefore making the inferno namespace visible to the sandboxed code.
<p>
From the <a href="http://pdos.csail.mit.edu/papers/vx32:usenix08/">vx32 paper</a>,
<p>
<quote>
"Vx32 is a multipurpose user-level sandbox that enables any application to 
load and safely execute one or more guest plug-ins, confining each guest 
to a system call API controlled by the host application and to a restricted 
memory region within the host’s address space."
</quote>
<p>
Inferno, being a virtual operating system, provides its own system call API to limbo applications. The same system calls are available as a C API for use by linked native libraries that appear as builtin modules or devices within the inferno environment. This API is a natural fit for building a Vx32 sandbox allowing native code of all kinds to run within inferno, which controls the namespace.
<p>
Please read the vx32 paper, download the code and play with it. I haven't
included the vx32 code in the lab. Instead this lab is more tutorial
in creating a new builtin module for inferno. This labs code, linked
to in the steps below, is all the code necessary to make vx32 appear
as a builtin.  I've done enough to show some simple examples working,
but I haven't defined the full system call interface.
<p>
So here are the steps in creating a new builtin module linkage.
<h3>module interface<h3>
Create the limbo module interface, e.g. 
<a href="http://inferno-lab.googlecode.com/svn/trunk/92/module/vxrun.m">/module/vxrun.m</a>.
I created the interface to closely resemble the vxrun
application in the vx32 distribution. The module contains
one function to load and run a native ELF executable.
<p>
Edit 
<a href="http://inferno-lab.googlecode.com/svn/trunk/92/module/runt.m">/module/runt.m</a> 
to include new include the new module
interface. This file includes all builtin modules and is used
later to generate a runtime C struct.
<h3>incorporate library code</h3>
Copy library and header files into inferno-os tree.
I copied vx32.h to 
<a href="http://inferno-lab.googlecode.com/svn/trunk/92/include/vx32.h">/include/vx32.h</a>. 
I created a new
libvx32 folder at the root of the tree and create a
dummy mkfile. I didn't copy all the source into the tree,
I cheated and just copied libvx32.a to /Linux/386/lib.
But the emu build will expect the folder and mkfile to 
exist. So this is a placeholder for now.  
<h3>add builting to libinterp</h3>
Implement the builtin linkage 
<a href="http://inferno-lab.googlecode.com/svn/trunk/92/libinterp/vxrun.c">/libinterp/vxrun.c</a>
This is the bulk of the work, where we call the vx32 API
and map the system calls defined in the codelet C library
that comes with the vx32 distribution, libvxc, to inferno's
API defined in /include/kernel.h.

A lot of this code was taken from vx32/src/vxrun/vxrun.c
and other pieces are more template code for builtin modules.
<p>
To get this to build we need to
edit the 
<a href="http://inferno-lab.googlecode.com/svn/trunk/92/libinterp/mkfile">/libinterp/mkfile</a>
 to include the new module,
with dependency on header file, generate header file. Add vxrun.$O to the
list of OFILES, add vxrun.m to the list of MODULES, and the following rules to ensure the module header, 
<a href="http://inferno-lab.googlecode.com/svn/trunk/92/libinterp/vxrunmod.h">vxrunmod.h</a>, is generated.
<pre>
vxrunmod.h:D: $MODULES
	rm -f $target && limbo -t Vxrun -I../module ../module/runt.m > $target
	
vxrun.$O: vxrunmod.h
</pre>
We can now compile libinterp.
<h3>edit emu config</h3>
The final step is to edit 
<a href="http://inferno-lab.googlecode.com/svn/trunk/92/emu/Linux/emu">/emu/Linux/emu</a>
 configuration file
and add the dependencies on the vxrun module and
the vx32 library.
We can now build a new emu that has the vx32 vxrun as
a builtin module.
<h3>test</h3>
We need a limbo command to call the module.
I included 
<a href="http://inferno-lab.googlecode.com/svn/trunk/92/vxinferno.b">vxinferno.b</a> in the lab code.
But it does nothing more than load the module and
call it passing in any command line arguments.

init(nil:ref Draw->Context, args:list of string)
{
	vxrun := load Vxrun Vxrun->PATH;
	vxrun->run(tl args);
}

I used the vx32-gcc to compile the native code. I included one example,
cat.c, that would test the system calls, open, read, write, from the inferno
namespace. Note that the name of the executable to call from inside
Inferno is the host pathname, because vx32 itself is not using the Inferno
system calls. This could be fixed by either changing the elf loader, or
by using the library call to load the ELF from memory.
<pre>
$ cd ~/vx32/src/vxrun
$ vxrungcc cat.c 
$ emu -s -r ~/inferno-os
; vxinferno /home/caerwyn/vx32/src/vxrun/_a.out /dev/drivers
#/ root
#c cons
#e env
#M mnt
...
</pre>
<p>
<h3>conclusion</h3>
This lab confirmed vx32 as a builtin to inferno would work. 
Now it needs to be implemented in full.


There is an effort to port 
<a href="http://www.midnight-labs.org/vxwin32/">vx32 to windows</a>, 
but it seems to have stalled.
I really hope that vx32 will get ported. 

