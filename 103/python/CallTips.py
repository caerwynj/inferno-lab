"""CallTips.py - An IDLE Extension to Jog Your Memory

Call Tips are floating windows which display function, class, and method
parameter and docstring information when you type an opening parenthesis, and
which disappear when you type a closing parenthesis.

"""
import re
import sys
import types
import __main__

class CallTips:


    def __init__(self):
        pass

    def fetch_tip(self, name):
        """Return the argument list and docstring of a function or class

        If there is a Python subprocess, get the calltip there.  Otherwise,
        either fetch_tip() is running in the subprocess itself or it was called
        in an IDLE EditorWindow before any script had been run.

        The subprocess environment is that of the most recently run script.  If
        two unrelated modules are being edited some calltips in the current
        module may be inoperative if the module was not the last to run.

        To find methods, fetch_tip must be fed a fully qualified name.

        """
        entity = self.get_entity(name)
        return get_arg_text(entity)

    def get_entity(self, name):
        "Lookup name in a namespace spanning sys.modules and __main.dict__"
        if name:
            namespace = sys.modules.copy()
            namespace.update(__main__.__dict__)
            try:
                return eval(name, namespace)
            except (NameError, AttributeError):
                return None

def _find_constructor(class_ob):
    # Given a class object, return a function object used for the
    # constructor (ie, __init__() ) or None if we can't find one.
    try:
        return class_ob.__init__.im_func
    except AttributeError:
        for base in class_ob.__bases__:
            rc = _find_constructor(base)
            if rc is not None: return rc
    return None

def get_arg_text(ob):
    """Get a string describing the arguments for the given object"""
    arg_text = ""
    if ob is not None:
        arg_offset = 0
        if type(ob) in (types.ClassType, types.TypeType):
            # Look for the highest __init__ in the class chain.
            fob = _find_constructor(ob)
            if fob is None:
                fob = lambda: None
            else:
                arg_offset = 1
        elif type(ob)==types.MethodType:
            # bit of a hack for methods - turn it into a function
            # but we drop the "self" param.
            fob = ob.im_func
            arg_offset = 1
        else:
            fob = ob
        # Try to build one for Python defined functions
        if type(fob) in [types.FunctionType, types.LambdaType]:
            argcount = fob.func_code.co_argcount
            real_args = fob.func_code.co_varnames[arg_offset:argcount]
            defaults = fob.func_defaults or []
            defaults = list(map(lambda name: "=%s" % repr(name), defaults))
            defaults = [""] * (len(real_args) - len(defaults)) + defaults
            items = map(lambda arg, dflt: arg + dflt, real_args, defaults)
            if fob.func_code.co_flags & 0x4:
                items.append("...")
            if fob.func_code.co_flags & 0x8:
                items.append("***")
            arg_text = ", ".join(items)
            arg_text = "(%s)" % re.sub("\.\d+", "<tuple>", arg_text)
        # See if we can use the docstring
        doc = getattr(ob, "__doc__", "")
        if doc:
            doc = doc.lstrip()
            pos = doc.find("\n")
            if pos < 0 or pos > 70:
                pos = 70
            if arg_text:
                arg_text += "\n"
            arg_text += doc[:pos]
    return arg_text
