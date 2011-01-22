import os
import sys
import string
import __main__

# These constants represent the two different types of completions
COMPLETE_ATTRIBUTES, COMPLETE_FILES = range(1, 2+1)

SEPS = os.sep
if os.altsep:  # e.g. '/' on Windows...
    SEPS += os.altsep

class AutoComplete:
    def __init__(self):
        pass

    def fetch_completions(self, what, mode):
        """Return a pair of lists of completions for something. The first list
        is a sublist of the second. Both are sorted.

        The subprocess environment is that of the most recently run script.  If
        two unrelated modules are being edited some calltips in the current
        module may be inoperative if the module was not the last to run.
        """
        if mode == COMPLETE_ATTRIBUTES:
            if what == "":
                namespace = __main__.__dict__.copy()
                namespace.update(__main__.__builtins__.__dict__)
                bigl = eval("dir()", namespace)
                bigl.sort()
                if "__all__" in bigl:
                    smalll = eval("__all__", namespace)
                    smalll.sort()
                else:
                    smalll = filter(lambda s: s[:1] != '_', bigl)
            else:
                try:
                    entity = self.get_entity(what)
                    bigl = dir(entity)
                    bigl.sort()
                    if "__all__" in bigl:
                        smalll = entity.__all__
                        smalll.sort()
                    else:
                        smalll = filter(lambda s: s[:1] != '_', bigl)
                except:
                    return [], []

        elif mode == COMPLETE_FILES:
            if what == "":
                what = "."
            try:
                expandedpath = os.path.expanduser(what)
                bigl = os.listdir(expandedpath)
                bigl.sort()
                smalll = filter(lambda s: s[:1] != '.', bigl)
            except OSError:
                return [], []

        if not smalll:
            smalll = bigl
        return smalll, bigl

    def get_entity(self, name):
        """Lookup name in a namespace spanning sys.modules and __main.dict__"""
        namespace = sys.modules.copy()
        namespace.update(__main__.__dict__)
        return eval(name, namespace)
        
