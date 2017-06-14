# NAME
lab 58 - Fallible software

# NOTES
"Even as the clock ticks, better and better computer support for the creative spirit is evolving." - Dan Ingalls.

How does computer support evolve and interact with the creative spirit?

Doug Englebart tackled a related question, "How can a computer support a problem solver's intellect?" Englebart's solution was a form of recursion called Bootstrapping. Build tools to help build better tools. The better tools would augment the programmers abilities to help them on their way to bootstrap the next system. A significant aspect of the bootstrapping philosophy was that the researchers used the tools they build.

The Smalltalk researchers took those ideas to heart. The [Design Principles of Smalltalk](http://www.cs.virginia.edu/~evans/cs655/readings/smalltalk.html) followed this evolution cycle explicitly:

- Build an application program within the current system (make an observation)
- Based on that experience, redesign the language (formulate a theory)
- Build a new system based on the new design (make a prediction that can be tested)


The point I want to emphasize is that both the system improved and the researchers learned during each cycle. This may be why constructionist learning has figured so prominently in Smalltalk's history. The Smalltalk researchers learned how to build systems by building them. But once completed they had a better system to use to start the process of building the next system: the computer support evolved with them.

Alan Kay and Dan Ingalls, original members of the Smalltalk team, went on to create Squeak. A successor to Smalltalk-80, it was built as a system for kids to build and discover their way to better understanding of math and science. Kay has written about the [Story of Squeak](http://users.ipa.net/~dwighth/squeak/oopsla_squeak.html), which closely follows the bootstrapping philosophy, including using Smalltalk to implement the Squeak system right down to the VM. And still Alan Kay doesn't see Squeak as an end in itself. Squeak is meant to be discarded, a stepping stone for the person using it to the next system that will provide even better support.

To get back to answering my original question, the creative process is a bootstrapping process. We learn by making things. And in the context of programming, there exists a kind of symbiosis between programmer and computer where the computer also learns new processes as we bootstrap new systems from old ones. The created system then becomes the context for the next system, and so it evolves, and with each evolution better supporting the niche of the creative spirit it is serving.

To further illustrate these ideas and reinforce the point that the computer is "learning" too, I point you to a fantastic talk given by Ken Thompson to the ACM, Reflections on Trusting Trust](http://www.acm.org/classics/sep95/).

Inferno is several generations along the bootstrap timeline. It was bootstrapped from Plan 9, which was bootstrapped from research UNIX, which was bootstrapped from earlier, more primitive UNIX systems way back to UNIX implemented in assembly.

The question then that begs to be asked is, what's next? This is not just a question about the system but also about the person (or people) developing it.

My first steps along this path have been to start thinking about systems rather than individual tools. I've tried to create an Inferno collection of software that's more tightly aligned with the things I need. I want to reduce the overall size but keeping the same power, or even increasing it. I've been trying to consider all trade-offs in complexity versus benefit. It's an attempt to bootstrap myself and the system to get better computer support for the creative spirit, hoping both will evolve as I keep pushing on the system.

I feel I could have chosen Squeak, Plan 9, plan9ports, or a lisp environment as a starting point. But I've developed such a comfort level with Inferno I'd find it hard now to switch. I feel I've already begun to mould Inferno to my needs, even as these needs are changing.

