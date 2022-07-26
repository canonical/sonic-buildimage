# Add inputs and outputs from these tool invocations to the build variables 
CC := g++

C_SRCS += \
../src/dhcp_device.cpp \
../src/dhcp_devman.cpp \
../src/dhcp_mon.cpp \
../src/main.cpp 

OBJS += \
./src/dhcp_device.o \
./src/dhcp_devman.o \
./src/dhcp_mon.o \
./src/main.o 

C_DEPS += \
./src/dhcp_device.d \
./src/dhcp_devman.d \
./src/dhcp_mon.d \
./src/main.d 


# Each subdirectory must supply rules for building sources it contributes
src/%.o: src/%.cpp
	@echo 'Building file: $<'
	@echo 'Invoking: GCC C Compiler'
	$(CC) -O3 -g3 -Wall -I$(PWD)/../sonic-swss-common/common -c -fmessage-length=0 -MMD -MP -MF"$(@:%.o=%.d)" -MT"$(@)" -o "$@" "$<"
	@echo 'Finished building: $<'
	@echo ' '
