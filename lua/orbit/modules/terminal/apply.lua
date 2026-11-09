-- :source assigns a separate script ID; require() inherits the caller's startup ID.
-- This distinguishes owned writes from same-value user writes while OptionSet is suppressed.
require("orbit.modules.terminal.shell").apply_pending()
