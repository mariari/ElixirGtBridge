ExUnit.start()

# The bridge boots fast (View.register_all and Xref indexing run in
# the background).  Tests that hit Xref need the index populated
# before assertions, so block here once.
GtBridge.Xref.wait_until_ready()
