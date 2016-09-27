using MetaPkg
using Base.Test

MetaPkg.dry_run()

# just check that they run without error
spec = MetaPkg.load_meta("MetaGL")
spec = MetaPkg.load_meta("MetaGL", Pkg.dir("MetaPkg","requires"))
MetaPkg.add("MetaGL")
MetaPkg.add("MetaGL", dir = Pkg.dir("MetaPkg","requires"))
MetaPkg.rm("MetaGL")
MetaPkg.free("MetaGL")
MetaPkg.checkout("MetaGL")
MetaPkg.checkout("MetaGL", "dev")
