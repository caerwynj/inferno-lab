#!/dis/python26

import pyxp
from acmewin import Acmewin

win = Acmewin()
win.writebody("hello, world!\n\n\n")
win.tagwrite("Hello")

win.writebody("goodbye")
win.replace("/goodbye/", "GOODBYE")

win.select(",")
win.show()

while True:
    (c1, c2, q0, q2, flag, nr, r) = win.getevent()
    if c2 in "xX":
        if flag & 2:
            (c1, c2, q0, q2, flag, nr, r) = win.getevent();
        if c2 == "x" and r == "Del":
            # print("Del")
            win.delete()
            break
        if c2 in "Xx" and r == "Hello":
            win.writebody("hello ")
    if c1 == "K" and c2 == "I":
        # print("insert " + r)
        ch = r[0]
        while q0 >= 0 and not (ch in " \t\r\n"):
            sss = win.read(q0, q0+1)
            if not sss:
                print("empty sss %d" % q0)
                sss = " "
            ch = sss[0]
            q0 -= 1
        if q0 < 0 and not(ch in " \t\r\n"):
            q0 = 0
        else:
            q0 += 2
        ss = win.read(q0,q2)
        print(ss)
# print("exiting from loop");
