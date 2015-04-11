# A Simple Grid Part 2 #

I want to show you a few more key points about inferno that are useful in building a grid. I'll show a really simple example of feeding data to all the worker processes.

Setup the grid as described in my last post.

This example is a multicore grep(1), so I want to send filenames to multiple grep workers. The are many different ways of doing this. The point here is to show more features of inferno that highlight its special qualities.

One such quality is that rcmd exports the local namespace to the remote command; we can use this to supply information to control the remote processes. The namespace is mounted on /n/client. To see this try,
```
   	% rcmd -A ${nextcpu} ls /n/client
```
Remember there's a lot more there than just a disk filesystem. We can create named pipes and feed data from one local to many remote processes through this pipe(3).

Make a named pipe
```
   	% mkdir /tmp/rpipe
   	% bind '#|' /tmp/rpipe
```
A simple example using the pipe (start the reading process first),
```
   	% rcmd -A ${nextcpu} cat /n/client/tmp/rpipe/data1 &
   	% du -a > /tmp/rpipe/data
```
I defined rsplit in my last post, but it only worked for .dis commands so I'm going to tweak it to work with sh braced blocks (another important inferno quality).
```
   fn rsplit {
   	args := $*
   	rpid := ()
   	for i in `{ndb/regquery -n svc rstyx} {
   		rcmd -A $i sh -c ${quote $"args }&
   		rpid = $apid $rpid
   	}
   	for i in  /prog/ ^ $rpid ^/wait {read < $i  } >/dev/null >[2=1]
   }
```
I'm going to use the command fs(1) to walk a file tree and print the paths. For this example I'm going to have it print all limbo source files.
```
   fn limbofiles {
   	fs print  {select {mode -d}  {filter -d {match -ar '.*\.(b|m)$'} {walk /appl}} } 
   }
```
Now I'm going to tie the pipe, fs, and rsplit together to get a distributed grep.
```
   fn lk {
   	re = $1
   	bind '#|' /tmp/rpipe
   	rsplit {
   		re=`{cat /n/client/env/re}; 
   		getlines {grep -i $re $line /dev/null} < /n/client/tmp/rpipe/data1
   	}&
   	sid := $apid
   	limbofiles > /tmp/rpipe/data
   	read < /prog/ ^ $sid ^ /wait  >/dev/null >[2=1]
   }
```
A few things to note about that. I set the environment variable 're' to the first argument of lk. The env(3) filesystem is also exported as part of our rcmd namespace, so I can read the value of 're' from any worker,
```
   	re=`{cat /n/client/env/re}
```
I use the sh-std(1) builtin 'getlines' to read one line at a time from the pipe and run grep (the /dev/null is to force grep to print filenames). The last line is there to wait for the rsplit command to finish.

You can run lk as follows,
```
   	% lk wmexport
```