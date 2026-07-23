ExUnit.start()

# The hot-reload and module-creator examples recompile modules by design,
# so silence the "redefining module" warnings that would otherwise flood
# the run.
Code.put_compiler_option(:ignore_module_conflict, true)

# Xref no longer indexes at VM boot; it starts on bridge startup (a
# listener spinning up), which the test VM never does.  Trigger it here
# the way a listener would, then block until the index is populated so
# tests that hit Xref don't race the background indexer.
GtBridge.Xref.start_indexing()
GtBridge.Xref.wait_until_ready()
