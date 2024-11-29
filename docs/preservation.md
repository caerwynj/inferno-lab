# Digital Preservation
* 110 inferno archive edition
* trainspotting. Collecting emus for different platforms.
* Inferno 1st edition revisted

### inferno archive edition

I've been occupied recently with archiving my digital media. I've been copying home videos on DV tapes to hard-disk, ripping audio CD's to WAV files, gathering photo collections, and trying to copy documents from Iomega disks, floppies, and my dusty old Acorn RiscPC.

My father recently scanned and sent me all his photographs of me and my siblings growing up; he also included pictures of himself and my mother when they met in Africa. With technology today each generation can build a digital library of family history to hand on to the next generation. In the past a family album may have been passed on to only one person. The accumulation of digital data still presents problems. It requires discipline to store files that are open and not locked into devices or proprietary formats.

With digital preservation in mind I've tried to use file formats recommended for long term archiving. WAV files for audio, DV for video, JPG and PNG for pictures, PDF for documents, and plain text.

Today the storage media is a 1TB external hard-disk. In my current computing environment I'm plugging that disk via USB into computers running Windows 7, Ubuntu, MacOSX, RiscOS, and Raspian. Ideally I'd be able to launch an application from the hard-disk that'd be able to playback the archived media on any of these host systems. This is where Inferno enters the picture.

Based on the criteria for selecting the file types, (non-proprietary, well documented, wide support) all the host systems should support the files natively, or a download can be easily found that will. However, the challenge is to get Inferno to do it nearly as well and work with a single set of tools everywhere. The tools are then preserved with the media on the disk.

The target functionality for an archival inferno edition is the following:

* Display pictures (JPG, PNG, GIF)
* Playback audio (WAV)
* Playback video (AVI-DV, MPEG-2)
* View ebooks (ePub3.0)
* View documents (Plain text, HTML4.0, PDF, DjVu?)
* Playback MIDI (built-in synethsizer)
* Mount disk images, archives, and file systems
* Compress or decompress files (gzip, bzip2)

Another important aspect of this is to have a collection of emulators that run on all the target platforms. I started this project in the inferno-bin repository a while ago. But it needs updating and the discipline to keep updating it. Ultimately the system interface of EMU needs to be locked down to give the freedom to run dis well into the future without the need to recompile.

Here's where we are with support inside Inferno:

	File type	Inferno support
	JPG, PNG	Supported by wm/view
	WAV	Supported by wavplay
	MIDI	Limited support by midiplay
	ePub	Support for older OEB versions in ebook/ebook. I've started updating to support ePub standard.
	Plain text	Supported
	HTML4.0	Limited support in Charon
	PDF	Unsupported, but MJL's PDF library are the beginnings of limited support
	AVI-DV	No support
	MPEG-2	Some support for an MPEG device. Could try to use Raspberry-Pi device support for MPEG-2
	tar, gzip	Supported
	bzip2	Unsupported
