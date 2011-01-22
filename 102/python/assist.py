#!/dis/python26

import sys
from acmewin import Acmewin
import spell

win = Acmewin(int(sys.argv[1]))
outwin = Acmewin(0)

while True:
    (c1, c2, q0, q2, flag, nr, r) = win.getevent()
    if c2 in "xX":
        if flag & 2:
            win.getevent()
        if flag & 8:
            win.getevent()
            win.getevent()
        win.writeevent(c1, c2, q0, q2)
        if c2 == "x" and r == "Del":
            outwin.delete()
            break
    if c1 == "K" and c2 == "I":
        ch = r[0]
        if ch in " \t\r\n":
            outwin.replace(",", "")
            continue
        while q0 >= 0 and not (ch in " \t\r\n"):
            sss = win.read(q0, q0+1)
            if not sss:
                # print("empty sss %d" % q0)
                sss = " "
            ch = sss[0]
            q0 -= 1
        if q0 < 0 and not(ch in " \t\r\n"):
            q0 = 0
        else:
            q0 += 2
        ss = win.read(q0,q2)
        lastcorrect = spell.correct(ss)
        outwin.replace(",", lastcorrect)
