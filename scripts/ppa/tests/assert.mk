# make 层单测共用的断言宏。
#
# 用法：include 本文件后
#   $(call assert,<名称>,<实际值>,<期望值>)
# 收集失败到 FAILURES；测试套件的默认目标据此决定退出码。
FAILURES :=

define assert
$(if $(filter-out x$(3),x$(2)),\
  $(warning FAIL $(1): got "$(2)" want "$(3)")$(eval FAILURES += $(1)),\
  $(info ok   $(1)))
endef

# 各测试套件在自己的默认目标里 include 本段逻辑：
#   ifneq ($(strip $(FAILURES)),)
#   	@echo "FAILED: $(FAILURES)"; exit 1
#   else
#   	@echo "<suite>: all assertions passed"
#   endif
