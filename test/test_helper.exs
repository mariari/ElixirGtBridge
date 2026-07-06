ExUnit.start()

# Xref no longer indexes at VM boot; it starts on bridge startup (a
# listener spinning up), which the test VM never does.  Trigger it here
# the way a listener would, then block until the index is populated so
# tests that hit Xref don't race the background indexer.
GtBridge.Xref.start_indexing()
GtBridge.Xref.wait_until_ready()
