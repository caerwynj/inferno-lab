#!/dis/python

import sys
from acmewin import Acmewin
import AutoComplete
import CallTips
import threading

win = Acmewin(int(sys.argv[1]))
#win = Acmewin(27)
outwin = Acmewin(0)
outwin.ctlwrite("name PyAssist+\n")
outwin.tagwrite("Import ")

autocom = AutoComplete.AutoComplete()
completions = None
ct = CallTips.CallTips()
exiting = 0

def getexpression(q0, q1, ch):
    while q0 >= 0 and not (ch in " \t\r\n=():+-*/%<>"):
        sss = win.read(q0, q0+1)
        if not sss:
            sss = " "
        ch = sss[0]
        q0 -= 1
    if q0 < 0 and not(ch in " \t\r\n=():+-*/%<>"):
        q0 = 0
    else:
        q0 += 2
    ss = win.read(q0,q1)
    # read returns more bytes than we ask for!
    return ss[:q1-q0]


def binary_search(s, completsions):
    """Find the first index in completions where completions[i] is
    greater or equal to s, or the last index if there is no such
    one."""
    i = 0; j = len(completions)
    while j > i:
        m = (i + j) // 2
        if completions[m] >= s:
            j = m
        else:
            i = m + 1
    return min(i, len(completions)-1)

def complete_string(s, completions):
    """Assuming that s is the prefix of a string in completions,
    return the longest string which is a prefix of all the strings which
    s is a prefix of them. If s is not a prefix of a string, return s."""
    first = binary_search(s, completions)
    if completions[first][:len(s)] != s:
        # There is not even one completion which s is a prefix of.
        return s
    # Find the end of the range of completions where s is a prefix of.
    i = first + 1
    j = len(completions)
    while j > i:
        m = (i + j) // 2
        if completions[m][:len(s)] != s:
            j = m
        else:
            i = m + 1
    last = i-1

    if first == last: # only one possible completion
        return completions[first]

    # We should return the maximum prefix of first and last
    first_comp = completions[first]
    last_comp = completions[last]
    min_len = min(len(first_comp), len(last_comp))
    i = len(s)
    while i < min_len and first_comp[i] == last_comp[i]:
        i += 1
    return first_comp[:i]

class WinWorker(threading.Thread):

    def __init__(self, win):
        threading.Thread.__init__(self)
        self.win = win

    def run(self):
        while True:
            (c1, c2, q0, q1, flag, nr, r) = self.win.getevent()
            if c2 in "xX":
                if flag & 2:
                    (c1, c2, q0, q1, z, nr, r) = self.win.getevent()
                if flag & 8:
                    ea = self.win.getevent()
                    na = ea[5]
                    self.win.getevent()
                else:
                    na = 0
                if q1 > q0 and nr == 0:
                    r = self.win.read(q0, q1)
                if na:
                    r += " " + ea[6]
                args = r.split()
                if args[0] == "Del":
                    self.win.ctlwrite("delete\n")
                    exiting = 1
                    break
                elif args[0] == "Import":
                    try:
                        __import__(args[1])
                    except:
                        print("import error")
                else:
                    self.win.writeevent(c1, c2, q0, q1)

worker = WinWorker(outwin)
worker.start()

while True:
    if exiting:
        break
    (c1, c2, q0, q1, flag, nr, r) = win.getevent()
    if c2 in "xX":
        if flag & 2:
            win.getevent()
        if flag & 8:
            win.getevent()
            win.getevent()
        win.writeevent(c1, c2, q0, q1)
        if c2 == "x" and r == "Del":
            outwin.delete()
            break
    if c1 == "K" and c2 == "I":
        ch = r[0]
        if ch == "\t" and lastel != None and completions != None:
            prefix = complete_string(lastel, completions)
            s = "#%d,#%d" % (q0, q1)
            win.replace(s, prefix[len(lastel):])
            continue
        if ch in " \t\r\n=):+-*/%<>":
            outwin.replace(",", "")
            completions = None
            lastel = None
            continue
        ss = getexpression(q0, q1, ch)
        # print("expression: " + ss)
        lastel = ss.split(".")[-1]
        smalll, bigl = [], []
        if ch == ".":
            smalll, bigl = autocom.fetch_completions(ss[:-1], AutoComplete.COMPLETE_ATTRIBUTES)
        elif ch == "(":
            ss = getexpression(q0-1, q1, "z")
            s = ct.fetch_tip(ss[:-1])
            outwin.replace(",", s + "\n")
            continue
        prefix = ""
        if len(smalll) == 0 and completions != None and lastel != None:
            prefix = complete_string(lastel, completions)
            for i in completions:
                if i[:len(prefix)] == prefix:
                    smalll.append(i)
        elif len(smalll) > 0:
            completions = smalll
        if len(smalll) > 0:
            outwin.replace(",", "")
            for i in smalll:
                outwin.writebody(i + "\n")
            
