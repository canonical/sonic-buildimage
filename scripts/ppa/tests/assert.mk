# Shared assertion macro for make-level unit tests.
#
# Usage: after including this file
#   $(call assert,<name>,<actual value>,<expected value>)
# Failures accumulate into FAILURES; each test suite's default target
# uses it to decide its exit code.
FAILURES :=

# Real string equality, not $(3)'s word-membership in $(2) (the bug this
# replaces: the previous $(filter-out x$(3),x$(2)) form only prepends "x" to
# the front of each whole argument, so once $(3) has more than one word --
# e.g. $(call assert,n,a,a a) -- "x" only lands on $(3)'s first word, leaving
# its other words as bare filter-out patterns that can match an unrelated
# $(2); that let a real mismatch report "ok"). $(2) equals $(3) exactly iff
# removing every occurrence of $(3) from $(2) AND every occurrence of $(2)
# from $(3) both leave nothing behind; checking both directions (not just
# one) also catches the case where $(2) is $(3) repeated (e.g. "a" vs "aa").
define assert
$(if $(strip $(subst $(3),,$(2))$(subst $(2),,$(3))),\
  $(warning FAIL $(1): got "$(2)" want "$(3)")$(eval FAILURES += $(1)),\
  $(info ok   $(1)))
endef

# Each test suite includes this logic in its own default target:
#   ifneq ($(strip $(FAILURES)),)
#   	@echo "FAILED: $(FAILURES)"; exit 1
#   else
#   	@echo "<suite>: all assertions passed"
#   endif
