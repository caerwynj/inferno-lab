lab 88 - degrees of freedom

The Vitanuova downloads page has historical snapshots of Inferno source from 1996 to 2003 containing all three editions before Inferno went open source. I was curious to see how well Inferno has sustained a standard set of interfaces over the last ten years so I downloaded all of them and poked around.

The biggest overall change came with 4th edition, when many parts of the system were upgraded, including the Styx protocol, several builtin modules, dis format, the limbo language and VM. Also, significantly, Inferno adopted open source licenses granting developers the freedom to modify any part of the system: something that might impact sustainability for good or ill.

While every edition prior to 4th has had some interfaces changed, these changes did not break backwards compatibility. A 3rd edition emu can run dis code from the 1st edition archive.

The difference between 3rd and 4th was large enough that limbo code needed to be ported, or at the very least recompiled, to run on the new emu.

The Sys interface is evolving still with additions made since 4th edition was released. These types of changes, adding a function or a new constant, do not break backward compatibility, but in a network of emus where there is diversity of versions, link typechecks do fail when a module is expecting an interface newer than the one available. Where is the standard interface here? This problem seems to violate some of the core ideas of Inferno, and Inferno doesn't provide an easy way of working around compatibility issues with builtin modules.

Inferno's core idea is to provide standard interfaces that free content and service providers from concern of the details of diverse hardware, software, and networks over which their content is delivered. (/sys/doc/bltj.ms)

The BLTJ paper describing Inferno listed the several dimensions of portability and versatility provided by the OS,


- Portability across processors: it currently runs on Intel, Sparc, MIPS, ARM, HP-PA, and PowerPC architectures and is readily portable to others.
- Portability across environments: it runs as a stand-alone operating system on small terminals, and also as a user application under Windows NT, Windows 95, Unix (Irix, Solaris, FreeBSD, Linux, AIX, HP/UX) and Plan 9. In all of these environments, Inferno applications see an identical interface.
- Distributed design: the identical environment is established at the user's terminal and at the server, and each may import the resources (for example, the attached I/O devices or networks) of the other. Aided by the communications facilities of the run-time system, applications may be split easily (and even dynamically) between client and server.
- Minimal hardware requirements: it runs useful applications stand-alone on machines with as little as 1 MB of memory, and does not require memory-mapping hardware.
- Portable applications: Inferno applications are written in the type-safe language Limbo, whose binary representation is identical over all platforms.
- Dynamic adaptability: applications may, depending on the hardware or other resources available, load different program modules to perform a specific function. For example, a video player application might use any of several different decoder modules.

Now that we have a decade of Inferno history, how many of the above degrees of freedom still hold when the whole time span is considered as one network of interconnected emus?

Don't standard interfaces also imply standard across time? A network of emus can not be expected to upgrade all at the same time. A standard is also a constraint against change in an interface. One degree of freedom is expressly limited; keep the abstraction constant.

The dilemma faced is whether to freeze an interface to provide long term compatibility based on a standard, but risk the possibility of being held back from adopting new ideas and becoming irrelevant, or to keep changing interfaces to solve new problems but pay the cost of compatibility problems.

In general it seems filesystems, namespaces and textual interfaces all lend well to creating a sustainable software environment. However, the more complex limbo language and module interfaces have shown themselves to be not so well preserved. By comparison, maybe unfairly because of the different goals of the creators, see how the works of Knuth are intended to withstand time. He specifically structures his software so that incompatibilities do not creep in, such as leaving no undefined gaps in font tables so that no one is tempted to fill them (TeX Book), or defining instructions to fill all 256 possible slots in MMIX, and making his source readable but not permitting edits except through his CWEB change file system. Knuth's software is the only kind I know of that take seriously the problem of long term compatibility.

It would be nice to run 1st edition dis code in a current emu if for no other reason than to prove the sustainability of infernos standard interfaces, but a major barrier to that is the need to bind in old Sys and Draw modules. I assume that compatibility to older interfaces should be provided through limbo modules so that the emu doesn't bear the extra weight and complexity of carrying multiple builtin implementations. There is no way to override where a builtin module is loaded from, though this might be a nice feature. For example, if /dev/dis/draw.dis represented the builtin draw module, I might bind limbo implementation over it, so that a load Draw "$Draw", would take the compatibility simulation over the builtin. (This might also work nicely going the other way so that we could bind builtin modules over limbo modules for optimization.)

This is not possible for Sys however, because we can't simulate variadic args in limbo (e.g., sys->print). A solution to this would be nice! But an alternative to providing more mechanism is simply to freeze the various interfaces.
