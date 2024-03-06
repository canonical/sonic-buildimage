#
# Copyright (c) 2020-2024 NVIDIA CORPORATION & AFFILIATES.
# Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Firmware pending update checker and installer

COMPONENT_VERSIONS_FILE = component-versions
$(COMPONENT_VERSIONS_FILE)_SRC_PATH = $(PLATFORM_PATH)/component-versions

SONIC_MAKE_FILES += $(COMPONENT_VERSIONS_FILE)

MLNX_FILES += $(COMPONENT_VERSIONS_FILE)

export COMPONENT_VERSIONS_FILE
