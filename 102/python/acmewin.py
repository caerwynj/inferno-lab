import pyxp

class AcmeException(Exception):
    pass

class Acmewin(object):

    def __init__(self, winid=0):
        self.client = pyxp.Client("tcp!localhost!6666")
        ctlpath = "/mnt/acme/new/ctl"
        if winid != 0:
            ctlpath = "/mnt/acme/%d/ctl" % winid
        self.ctl = self.client.open(ctlpath, 0x02)
        (id, nt ,nb, isdir, ismod, width, font, tabwidth) = self.ctl.readlines().next().split()
        self.id = id
        bodypath = "/mnt/acme/%s/body" % id
        self.body = self.client.open(bodypath, 0x02)
        self.addr = None
        self.tag = None
        self.event = None
        self.data = None
        self.buf = ""
        self.bufp = 0
        self.nbuf = 0

    def writebody(self, s):
        self.body.write(s)

    def _openfile(self, f):
        path = "/mnt/acme/%s/%s" % (self.id, f)
        f = self.client.open(path, 0x02)
        return f

    def replace(self, addr, repl):
        if self.addr is None:
            self.addr = self._openfile("addr")
        if self.data is None:
            self.data = self._openfile("data")
        self.addr.write(addr)
        self.data.write(repl)

    def read(self, q0, q1):
        if self.addr is None:
            self.addr = self._openfile("addr")
        if self.data is None:
            self.data = self._openfile("data")
        s = ""
        m = q0
        while m < q1:
            buf = "#%d" % m
            self.addr.write(buf)
            ss = self.data.read(256)
            s += ss
            m += len(s)
        return s

    def show(self):
        self.ctl.write("show\n")

    def setaddr(self, addr):
        if self.addr is None:
            self.addr = self._openfile("addr")
        self.addr.write(addr)

    def select(self, addr):
        self.setaddr(addr)
        self.ctl.write("dot=addr\n")

    def tagwrite(self, s):
        if self.tag is None:
            self.tag = self._openfile("tag")
        self.tag.write(s)

    def ctlwrite(self, s):
        self.ctl.write(s)

    def _getec(self):
        if self.nbuf == 0:
            self.buf = self.event.read()
            self.nbuf = len(self.buf)
            if self.nbuf <= 0:
                print("read event error")
            self.bufp = 0
        self.nbuf -= 1
        ret = self.buf[self.bufp]
        self.bufp += 1
        return ret
    
    def _geten(self):
        s = ""
        c = self._getec()
        while c in "0123456789":
    	    s += c
    	    c = self._getec()
        return int(s)
        
    def getevent(self):
        if self.event is None:
            self.event = self._openfile("event")
        c1 = self._getec()
        c2 = self._getec()
        q0 = self._geten()
        q1 = self._geten()
        flag = self._geten()
        nr = self._geten()
        nb = 0
        r = ""
        for i in range(nr):
            r += self._getec()
        c = self._getec()
        if c != "\n":
            print("event syntax error")
        return (c1, c2, q0, q1, flag, nr, r)

    def writeevent(c1, c2, q0, q1):
        if self.event is None:
            self.event = self._openfile("event")
        self.event.write("%c %c %d %d\n" % c1, c2, q0, q1)
    
    def delete(self):
        self.ctlwrite("del\n")
        self.addr = None
        self.body = None
        self.data = None
        self.ctl = None
        self.event = None
