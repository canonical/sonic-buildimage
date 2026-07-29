# Self-test for scripts/ppa/tests/assert.mk itself: every other suite's
# ability to fail depends on assert's equality check actually being an
# equality check. The bug this guards against (assert.mk's
# $(filter-out x$(3),x$(2)) form was a word-membership test, not string
# equality: $(call assert,n,a,a a) printed "ok") would let every assertion
# in functions_test.mk/rules_test.mk/query_test.mk pass unconditionally
# whenever the expected value happened to be a multi-word string containing
# the actual value as one of its words. Verify the opposite here: that a
# real mismatch, and specifically that same multi-word shape, both land in
# assert's own FAILURES accumulator.
# Usage: make -s -f scripts/ppa/tests/assert_test.mk

include scripts/ppa/tests/assert.mk

# Two deliberately-failing cases. assert's own $(warning FAIL mismatch: ...)
# / $(warning FAIL word-subset: ...) firing below is expected output of this
# suite, not a bug in it.
#   - a plain mismatch
$(call assert,mismatch,a,b)
#   - the regression this replaces: $(3) has more than one word, and $(2)
#     equals only one of them
$(call assert,word-subset,a,a a)

DELIBERATE_FAILURES := mismatch word-subset
ifeq ($(sort $(FAILURES)),$(sort $(DELIBERATE_FAILURES)))
$(info ok   assert records both a mismatch and a word-subset pair as FAIL)
else
$(info FAIL assert_test: expected exactly "$(DELIBERATE_FAILURES)" to fail, FAILURES is "$(FAILURES)")
FAILURES += self-check
endif
# Drop the two expected failures so they don't fail this suite itself; any
# other name that ends up in FAILURES past this point is a real regression.
FAILURES := $(filter-out $(DELIBERATE_FAILURES),$(FAILURES))

# A real match must still report ok and must not add to FAILURES, including
# the empty-string-vs-empty-string case some real assertions rely on (e.g.
# query_test.mk's local-ppa-pool-url-empty).
$(call assert,match,a,a)
$(call assert,match-empty,,)

.PHONY: default
default:
ifneq ($(strip $(FAILURES)),)
	@echo "FAILED: $(FAILURES)"; exit 1
else
	@echo "assert_test: all assertions passed"
endif
