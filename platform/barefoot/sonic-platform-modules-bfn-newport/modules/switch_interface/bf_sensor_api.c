/*
 * Copyright (c) 2021 Edgecore Networks Corporation
 *
 * This file is licensed under the terms of the GNU General Public
 * License version 2. This program is licensed "as is" without any
 * warranty of any kind, whether express or implied.
 *
 * device attribute handler implementation for bf sensor driver
 */

#define pr_fmt(fmt) "%s:%s: " fmt, KBUILD_MODNAME,  __func__

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/hwmon-sysfs.h>
#include "bf_module_util.h"
#include "bf_sensor_driver.h"

extern struct bf_sensor_drv_data *g_data;


ATTR_SHOW_STR_FUNC(debug,
    "+++DUMMY content+++\n"
    "sensor present:\n"
    "  0-->present\n"
    "  1-->unpresent\n"
    "  bit0-->sensor1, bit4-->sensor2\n"
    "  eg:\n"
    "  1.show present info: i2cget -f -y 2 0x1d 0x34\n"
    "\n"
    "sensor data:\n"
    "                    path\n"
    "  sensor1             81-0058\n"
    "  sensor2             82-0058\n"
    "                    sysfs\n"
    "  temp     :    temp1_input\n"
    "  fan_speed:    fan1_input\n"
    "  i_in     :    curr1_input\n"
    "  v_in     :    in1_input\n"
    "  p_in     :    power1_input\n"
    "  i_out    :    curr2_input\n"
    "  v_out    :    in2_input\n"
    "  p_out    :    power2_input\n"
    "  eg:\n"
    "  1.show data info: cat /sys/bus/i2c/devices/$path/hwmon/hwmon*/$sysfs\n"
    "sensor vendor, model, serial, version:\n"
    "  sensor1-->$bus = 81, $addr = 0x50\n"
    "  sensor2-->$bus = 82, $addr = 0x50\n"
    "  eg:\n"
    "  1.show all info: i2cdump -f -y $bus $addr\n"
    "---DUMMY content---\n"
)

ATTR_SHOW_NUM_FUNC(devnum, NUM_DEV)


ssize_t temp_show(struct device *dev, struct device_attribute *da,
                            char *buf)
{
    struct platform_device *pdev = to_platform_device(dev);
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    bf_print("pdev_id=%d, attr_name(%s) attr_idx=%d\n", pdev->id, da->attr.name, attr->index);
    return 0;
}
ssize_t temp_store(struct device *dev, struct device_attribute *da,
                            const char *buf, size_t count)
{
    struct platform_device *pdev = to_platform_device(dev);
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    bf_print("pdev_id=%d, attr_name(%s) attr_idx=%d\n", pdev->id, da->attr.name, attr->index);
    return count;
}
