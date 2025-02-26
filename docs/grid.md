# Grid
* 84 gridfs pattern (mapreduce)
* 83 lcmd local cpu
* 40 distributing data
* 38 Geryon's data sets
* 37 Geryon's mapreduce
* 36 Geryon's registry
* 35 Geryon, another Inferno grid
* 14 map reduce


.SH NAME
lab 14 - map reduce functional grid programming
.SH DESCRIPTION
I read about Google's
.A http://labs.google.com/papers/mapreduce.html MapReduce
from Rob Pike's
.A http://slashdot.org/article.pl?sid=04/10/05/1537242 interview
at slashdot.
At the same time I've been  studying Inferno's
.IR alphabet-grid (1)
and am wondering if I can implement
map reduce using alphabet.
.PP
Here's an imaginary example
.IP
.EX
% - {rng , | remote |
	mapreduce "{tq -1rm /n/tick/tick.bt} "{tock } |
	/create /tmp/result
}
.EE
.PP
Suppose that 
.B tick.bt
is a log of time spent on tasks where each record
is the timestamp, task and number of seconds
spent on the task that instance.
.I Rng
produces 1 or more date ranges. 
.I Remote
converts type 
.B /fd
to an endpoint.
.I Mapreduce
will then split a date range,
such as one year,
into
.I M
smaller date ranges.
For each
subrange it calls
.I rexec
passing it the address of an available node,
the subrange and map function as parameters.
.PP
The output from all the map functions
is directed to R endpoints.
The R parition function could be
.I "hash(key) mod R
as suggested in the paper.
Then
.I mapreduce
.IR rexec 's
a reduce worker,
which reads in all the data from
the endpoint, sorts it, and for each
key calls the reduce function with the
key and list of values (or /fd) as parameter.
In this example 
.IR tock ,
the reduce function,
sums all the time values for a task
and outputs the total.
.PP
I've made the example specific to 
.I tickfs
and the use of triads merely because I already have
these tools and makes it easier for me to grasp. 
The google paper
uses key, value pairs. I'm ignoring
all the other factors they consider,
such as fault tolerance, locality, 
and much else. 
.PP
Here's another example.
In the distribution on my homepage I include
a command 
.I nsearch 
for searching a 
.I tickfs
index. The command is given a list of keywords.
Given the first keyword, which might be a date range,
it builds an initial set of keys. It then partitions
this set among a fixed number of threads.
Each thread test the record coming in on a channel
against the index and the search term given as
parameter to the thread.
The reduce function would be an identity function,
simply passing through it's input.
This is a map, filter, reduce pipeline.
Alphabet seems to provide the tools to express
this whole query and more on the command line, including
distributing the processing among nodes.
.PP
The implementation needs somewhere to lookup the available list
of nodes. Administering all the nodes would
need some fancy fs that managed the status
of all executing workers. I'd keep this
to an absolute minimum for now.
.SH CONLUSION
This all sounds very promising but I don't know how to
implement it yet. Here are some more 
.A http://caerwyn.com/lab/14/notes notes
while I think this through.
.PP
The revelation for me is the importance
of functional programming to distributed computing.
It wasn't long ago (lab 1) that I discovered limbo
shell supported functional programming.
Alphabet takes this to the next level by defining
types. 
Alphabet-grid
provides the connection between processing modules
on distributed nodes. Altogether it provides
a framework for distributed computing I'm still
coming to grips with. It is a different way of thinking
about computing than I am used to.
.SH REFERENCES
.A http://labs.google.com/papers/mapreduce.html MapReduce
.A http://slashdot.org/article.pl?sid=04/10/05/1537242 Interview



