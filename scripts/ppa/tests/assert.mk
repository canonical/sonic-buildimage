# Shared assertion macro for make-level unit tests.
#
# Usage: after including this file
#   $(call assert,<name>,<actual value>,<expected value>)
# Failures accumulate into FAILURES; each test suite's default target
# uses it to decide its exit code.
FAILURES :=

define assert
$(if $(filter-out x$(3),x$(2)),\
  $(warning FAIL $(1): got "$(2)" want "$(3)")$(eval FAILURES += $(1)),\
  $(info ok   $(1)))
endef

# Each test suite includes this logic in its own default target:
#   ifneq ($(strip $(FAILURES)),)
#   	@echo "FAILED: $(FAILURES)"; exit 1
#   else
#   	@echo "<suite>: all assertions passed"
#   endif
