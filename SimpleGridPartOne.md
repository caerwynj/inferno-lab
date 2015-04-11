# A Simple Grid #

Here's a tutorial to setup a real simple grid using inferno. These instructions should work, although they may not be completely realistic, but hopefully they introduce you to the pieces you might use to build your own grid.

I'm going to setup multiple nodes but I'm going to do it all on a single machine. This example is still useful in the context of a multicore computer. I assume all the examples below are run in acme-sac.

A key piece to any inferno grid is the registry(4). We want to run only one registry in our grid. First edit /lib/ndb/local and set the registry value for the infernosite.
```
 	infernosite=
 		registry=localhost
```
I'm going to build up a small library of shell functions to start the pieces of the grid so I can do them over and over. Start acme-sac and create a new file called gridlib. Add each of the commands defined below to this file. We want to designate one node (acme-sac session) as the master, and several others as workers.

The following function launches the registry and exports the registry filesystem.
```
   fn masterinit {
   	ndb/cs
   	mount -A -c {ndb/registry} /mnt/registry
   	listen -A -v 'tcp!*!registry' {export /mnt/registry&}
   }
```
Each worker must mount the registry.
```
   fn workerinit {
   	ndb/cs
   	mount -A 'net!$registry!registry' /mnt/registry
   }
```
Open a new acme-sac editor to have running as a master server. Open 'win' and run masterinit.
```
   	% run gridlib
   	% masterinit
```
Each worker is going to export rstyx so it can run commands. We want everything we launch using the grid to register with the registry. The command 'newcpu' will register a new rstyx service.
```
   fn newcpu {
   	grid/reglisten -A -r svc rstyx 'tcp!*!0' {auxi/rstyxd&}
   }
```
Start a few more acme-sac editors and run the workerinit function from gridlib.
```
   	% run gridlib
   	% workerinit
   	% newcpu
```
If you 'ls' the contents of /mnt/registry from any of the nodes you should see all the services from the workers. Open /mnt/registry/index to get more detail. You can add more attributes to your services by giving them as arguments to reglisten.

Now lets run the same command simultaneously on all cpus. This command uses ndb/regquery to find all rstyx services, then on each uses rcmd to run a remote command. We do this in the background and gather the pids of each rcmd, which we'll use at the end to wait for all the jobs to finish.
```
   fn rsplit {
   	args := $*
   	rpid := ()
   	for i in `{ndb/regquery -n svc rstyx} {
   		rcmd -A $i $args &
   		rpid = $apid $rpid
   	}
   	for i in  /prog/ ^ $rpid ^/wait {read < $i  } >/dev/null >[2=1]
   }
```
And here's an example of running it.
```
   % rsplit math/linbench 200
      28.79 Mflops      0.2 secs
      24.72 Mflops      0.2 secs
      43.31 Mflops      0.1 secs
```
If you have a multicore machine you can try different number of nodes to peg the cpu.