#NAME
lab 55 - cut & paste

#NOTES
This work includes some enhancements for running inferno hosted on windows. These are small details, but do seem to make a difference.

First is cut & paste between host and inferno. I copied the code from drawterm to do this. The file `/dev/snarf` contains the windows clipboard. Typically one would say `bind /dev/snarf /chan/snarf` and everything works just great.

Second is window resizing. In this case the host window is resized but the inferno windows all stay the same. But this still improves it. It's nice to be able to resize the window. However, for this to work the toolbar needs to be moved to the top instead of the bottom of the screen.

Finally, I added `/dev/fullscreen`. Writing anything to the file cases inferno to toggle fullscreen mode.

To use the changes copy `devarch.c` and `win.c` to `/emu/Nt`, and `devcons.c` to `/emu/port`.

#POSTSCRIPT
These changes are now built into Acme SAC.
