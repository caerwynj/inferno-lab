#NAME
lab 78 - dynamic dispatch

#NOTES
While experimenting with creating my own alphabet-like interfaces I found this technique, which I think is fascinating, and I hope to use it soon in further experiments with persistent mounts, something I'll blog about in the future.

Here's a definition of a pick ADT that has some primitive types (I've left out the complete set to keep it short), and some helper functions to get the value from the pick.

	Value: adt {
	 getfd: fn(v: self ref Value): ref Sys->FD;
	 gets: fn(v: self ref Value): string;
	 send: fn(v: self ref Value, r: ref Value);
	  
	 pick {
	 S =>
	  i: string;
	 F =>
	  i: ref Sys->FD;
	 O =>
	  i: chan of ref Value;
	 }
	};

The thing to notice here is the recursive definition of the ADT. We don't need to define chan of string or chan of FD. The Value.O type is a channel that can handle anything of ref Value, all our primitive types including ... chan of ref Value.

So given a v : ref Value, we'd get, say, the file descriptor as follows,

	fd := v.getfd();
	
The pick value might already be Value.F in which case we get the file descriptor directly. On the other hand, it might be a channel, so we request the value from the channel. This is hidden away in the getfd() function so the caller doesn't know where the value will come from.

A channel is something that can bind our process to another process. This technique permits us to perform a kind of dynamic dispatch for a name, where at runtime we call a process that will supply us a value.

This is how getfd() is implemented:

	Value.getfd(v: self ref Value):ref Sys->FD
	{
	 pick xv := v{
	 O =>
	  replyc := chan of ref Value;
	  xv.i <-= ref Value.O(replyc);
	  return (<-replyc).getfd();
	 F =>
	  return xv.i;
	 }
	 raise typeerror('f', v);
	}

Let's walk through that code. As I said, if the value is a pick type of F we already have a file descriptor and return that. If it's a channel we create another channel of ref Value and send that down the channel to request a Value from another process, which should be waiting at the other end. We then call getfd() recursively on the value we receive from the reply chan.

Yes, there's recursion again. The process we are requesting a value from could send us a channel to another process, and if it did so we'd repeat the transaction.

Note, if we ever get the wrong type we just throw a type error.

There is a general protocol here that all processes follow that take part in this transaction.

When a process is started it is passed a request channel from which it should wait to receive a reply chan. It should then do its job and send the result down the reply chan.

The process might also be passed ref Values as arguments, which could be bound to other processes and so on.

Here's an example expression that we want evaluated using this technique,

	% xy mount {styxpersist {auth {dial tcp!host!styx}}}

Every module in that expression would implement the same interface, something like this,

	Xymodule: module {
	 init: fn();
	 run: fn(request: chan of ref Value, args: list of ref Value);
	};

Every module gets launched with an already created channel and is spawned its own process.

	runcmd(..., cmd: string, args: list of ref Value): ref Value
	{
	 m := loadmodule(cmd);
	 m->init();
	 ...
	 req := chan of ref Value;
	 spawn m->run(req, opts, args);
	 return ref Value.O(req);
	}

And finally, every process would follow a template like this,

	run(req: chan of ref Value, args: list of ref Value)
	{
	 while((replyc :=<-req) != nil){
	  # do some work to create  value
	  replyc.send(value);
	 }
	}

Lets step through the shell expression to see what is happening.

Mount requests an FD from its first argument, in this case styxpersist. Mount sends the reply chan and waits. Mount will exit once it's done, but styxpersist and the other processes will need to carry on running. Styxpersist requests a FD from auth, which requests one from dial. Dial creates the FD from dialing the remote host and returns it to auth, which authenticates on that FD and returns it to styxpersist.

Styxpersist relays bytes between the mount point and the file descriptor it obtained from its argument. If the connection closes it will request another file descriptor, and re-attach to the styx service. In this way we have a persistent connection.

All that we are passing around is channels and file descriptors. But this approach is very flexible, since inferno handles resources as files.

The channels also allow us a great deal of flexibility with the binding of a name to its value.

Lets review what the channels and the ADT described above let us do.

Given a value, the code bound to a method call on that value is determined at run time. The code bound to getfd() is dynamically dispatched. The similarity between this and OOP, especially smalltalk, is quite strong.

A lot of the object oriented techniques in smalltalk fall out from the method of dynamic dispatch used by all objects. "Sharing and reuse mechanisms (such as delegation) are not part of the object model per se but can be added simply by overriding the 'lookup' operation". (Kay et al [PDF])

There are two ways we are supporting dynamic dispatch.

We are sending the reply chan which allows the callee to forward it on and carry on receiving requests, allowing multiple senders even when requests haven't been completed.

We are also allowing channels to be returned and requests resent if that happens. So if a process can't handle a request, it can return a channel to another process, allowing the request to be sent to a 'higher' process to see if it can respond.

A combination of the above two can also be used.

I assume there are more strategies that could be implemented. I've scratched the surface.

There is some code to go with the lab. The code was derived from fs(1), which was derived from sh-alphabet(1). However, I don't think the specific technique I described above was used in either. The code does not yet implement the shell expression described above, but a simpler one,

	% xy mount {styxmon {auth {dial tcp!host!styx}}}
