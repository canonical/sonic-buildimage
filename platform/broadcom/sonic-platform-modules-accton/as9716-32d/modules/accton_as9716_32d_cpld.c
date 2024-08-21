/*
 * Copyright (C)  Brandon Chuang <brandon_chuang@accton.com.tw>
 *
 * This module supports the accton cpld that hold the channel select
 * mechanism for other i2c slave devices, such as SFP.
 * This includes the:
 *	 Accton as9716_32d CPLD1/CPLD2/CPLD3
 *
 * Based on:
 *	pca954x.c from Kumar Gala <galak@kernel.crashing.org>
 * Copyright (C) 2006
 *
 * Based on:
 *	pca954x.c from Ken Harrenstien
 * Copyright (C) 2004 Google, Inc. (Ken Harrenstien)
 *
 * Based on:
 *	i2c-virtual_cb.c from Brian Kuschak <bkuschak@yahoo.com>
 * and
 *	pca9540.c from Jean Delvare <khali@linux-fr.org>.
 *
 * This file is licensed under the terms of the GNU General Public
 * License version 2. This program is licensed "as is" without any
 * warranty of any kind, whether express or implied.
 */

#include <linux/module.h>
#include <linux/init.h>
#include <linux/slab.h>
#include <linux/device.h>
#include <linux/i2c.h>
#include <linux/version.h>
#include <linux/stat.h>
#include <linux/hwmon-sysfs.h>
#include <linux/delay.h>

#define I2C_RW_RETRY_COUNT				10
#define I2C_RW_RETRY_INTERVAL			60 /* ms */

static LIST_HEAD(cpld_client_list);
static struct mutex     list_lock;

struct cpld_client_node {
    struct i2c_client *client;
    struct list_head   list;
};

enum cpld_type {
    as9716_32d_fpga,
    as9716_32d_cpld1,
    as9716_32d_cpld2,
    as9716_32d_cpld_cpu
};

struct as9716_32d_cpld_data {
    enum cpld_type   type;
    struct device   *hwmon_dev;
    struct mutex     update_lock;
};

static const struct i2c_device_id as9716_32d_cpld_id[] = {
    { "as9716_32d_fpga", as9716_32d_fpga },
    { "as9716_32d_cpld1", as9716_32d_cpld1 },
    { "as9716_32d_cpld2", as9716_32d_cpld2 },
    { "as9716_32d_cpld_cpu", as9716_32d_cpld_cpu },
    { }
};
MODULE_DEVICE_TABLE(i2c, as9716_32d_cpld_id);

#define TRANSCEIVER_PRESENT_ATTR_ID(index)   	MODULE_PRESENT_##index
#define TRANSCEIVER_TXDISABLE_ATTR_ID(index)   	MODULE_TXDISABLE_##index
#define TRANSCEIVER_RXLOS_ATTR_ID(index)   		MODULE_RXLOS_##index
#define TRANSCEIVER_TXFAULT_ATTR_ID(index)   	MODULE_TXFAULT_##index
#define TRANSCEIVER_RESET_ATTR_ID(index)   	    MODULE_RESET_##index
#define CPLD_INTR_ATTR_ID(index)   	            CPLD_INTR_##index

enum as9716_32d_cpld_sysfs_attributes {
	CPLD_VERSION,
	ACCESS,
	/* transceiver attributes */
	TRANSCEIVER_PRESENT_ATTR_ID(1),
	TRANSCEIVER_PRESENT_ATTR_ID(2),
	TRANSCEIVER_PRESENT_ATTR_ID(3),
	TRANSCEIVER_PRESENT_ATTR_ID(4),
	TRANSCEIVER_PRESENT_ATTR_ID(5),
	TRANSCEIVER_PRESENT_ATTR_ID(6),
	TRANSCEIVER_PRESENT_ATTR_ID(7),
	TRANSCEIVER_PRESENT_ATTR_ID(8),
	TRANSCEIVER_PRESENT_ATTR_ID(9),
	TRANSCEIVER_PRESENT_ATTR_ID(10),
	TRANSCEIVER_PRESENT_ATTR_ID(11),
	TRANSCEIVER_PRESENT_ATTR_ID(12),
	TRANSCEIVER_PRESENT_ATTR_ID(13),
	TRANSCEIVER_PRESENT_ATTR_ID(14),
	TRANSCEIVER_PRESENT_ATTR_ID(15),
	TRANSCEIVER_PRESENT_ATTR_ID(16),
	TRANSCEIVER_PRESENT_ATTR_ID(17),
	TRANSCEIVER_PRESENT_ATTR_ID(18),
	TRANSCEIVER_PRESENT_ATTR_ID(19),
	TRANSCEIVER_PRESENT_ATTR_ID(20),
	TRANSCEIVER_PRESENT_ATTR_ID(21),
	TRANSCEIVER_PRESENT_ATTR_ID(22),
	TRANSCEIVER_PRESENT_ATTR_ID(23),
	TRANSCEIVER_PRESENT_ATTR_ID(24),
	TRANSCEIVER_PRESENT_ATTR_ID(25),
	TRANSCEIVER_PRESENT_ATTR_ID(26),
	TRANSCEIVER_PRESENT_ATTR_ID(27),
	TRANSCEIVER_PRESENT_ATTR_ID(28),
	TRANSCEIVER_PRESENT_ATTR_ID(29),
	TRANSCEIVER_PRESENT_ATTR_ID(30),
	TRANSCEIVER_PRESENT_ATTR_ID(31),
	TRANSCEIVER_PRESENT_ATTR_ID(32),
	TRANSCEIVER_PRESENT_ATTR_ID(33),
	TRANSCEIVER_PRESENT_ATTR_ID(34),
	TRANSCEIVER_TXDISABLE_ATTR_ID(33),
	TRANSCEIVER_TXDISABLE_ATTR_ID(34),
	TRANSCEIVER_RXLOS_ATTR_ID(33),
	TRANSCEIVER_RXLOS_ATTR_ID(34),
	TRANSCEIVER_TXFAULT_ATTR_ID(33),
	TRANSCEIVER_TXFAULT_ATTR_ID(34),
	TRANSCEIVER_RESET_ATTR_ID(1),
	TRANSCEIVER_RESET_ATTR_ID(2),
	TRANSCEIVER_RESET_ATTR_ID(3),
	TRANSCEIVER_RESET_ATTR_ID(4),
	TRANSCEIVER_RESET_ATTR_ID(5),
	TRANSCEIVER_RESET_ATTR_ID(6),
	TRANSCEIVER_RESET_ATTR_ID(7),
	TRANSCEIVER_RESET_ATTR_ID(8),
	TRANSCEIVER_RESET_ATTR_ID(9),
	TRANSCEIVER_RESET_ATTR_ID(10),
	TRANSCEIVER_RESET_ATTR_ID(11),
	TRANSCEIVER_RESET_ATTR_ID(12),
	TRANSCEIVER_RESET_ATTR_ID(13),
	TRANSCEIVER_RESET_ATTR_ID(14),
	TRANSCEIVER_RESET_ATTR_ID(15),
	TRANSCEIVER_RESET_ATTR_ID(16),
	TRANSCEIVER_RESET_ATTR_ID(17),
	TRANSCEIVER_RESET_ATTR_ID(18),
	TRANSCEIVER_RESET_ATTR_ID(19),
	TRANSCEIVER_RESET_ATTR_ID(20),
	TRANSCEIVER_RESET_ATTR_ID(21),
	TRANSCEIVER_RESET_ATTR_ID(22),
	TRANSCEIVER_RESET_ATTR_ID(23),
	TRANSCEIVER_RESET_ATTR_ID(24),
	TRANSCEIVER_RESET_ATTR_ID(25),
	TRANSCEIVER_RESET_ATTR_ID(26),
	TRANSCEIVER_RESET_ATTR_ID(27),
	TRANSCEIVER_RESET_ATTR_ID(28),
	TRANSCEIVER_RESET_ATTR_ID(29),
	TRANSCEIVER_RESET_ATTR_ID(30),
	TRANSCEIVER_RESET_ATTR_ID(31),
	TRANSCEIVER_RESET_ATTR_ID(32),
	CPLD_INTR_ATTR_ID(1),
	CPLD_INTR_ATTR_ID(2),
	CPLD_INTR_ATTR_ID(3),
	CPLD_INTR_ATTR_ID(4),
	
};

/* sysfs attributes for hwmon 
 */
static ssize_t show_interrupt(struct device *dev, struct device_attribute *da,
             char *buf);
static ssize_t show_status(struct device *dev, struct device_attribute *da,
             char *buf);
static ssize_t set_tx_disable(struct device *dev, struct device_attribute *da,
			const char *buf, size_t count);
static ssize_t access(struct device *dev, struct device_attribute *da,
			const char *buf, size_t count);
static ssize_t show_version(struct device *dev, struct device_attribute *da,
             char *buf);
static ssize_t get_mode_reset(struct device *dev, struct device_attribute *da,
			char *buf);
static ssize_t set_mode_reset(struct device *dev, struct device_attribute *da,
			const char *buf, size_t count);
static int as9716_32d_cpld_read_internal(struct i2c_client *client, u8 reg);
static int as9716_32d_cpld_write_internal(struct i2c_client *client, u8 reg, u8 value);

/* transceiver attributes */
#define DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(index) \
	static SENSOR_DEVICE_ATTR(module_present_##index, S_IRUGO, show_status, NULL, MODULE_PRESENT_##index)
#define DECLARE_TRANSCEIVER_PRESENT_ATTR(index)  &sensor_dev_attr_module_present_##index.dev_attr.attr

#define DECLARE_SFP_TRANSCEIVER_SENSOR_DEVICE_ATTR(index) \
	static SENSOR_DEVICE_ATTR(module_tx_disable_##index, S_IRUGO | S_IWUSR, show_status, set_tx_disable, MODULE_TXDISABLE_##index); \
	static SENSOR_DEVICE_ATTR(module_rx_los_##index, S_IRUGO, show_status, NULL, MODULE_RXLOS_##index);  \
	static SENSOR_DEVICE_ATTR(module_tx_fault_##index, S_IRUGO, show_status, NULL, MODULE_RXLOS_##index); 
	
#define DECLARE_SFP_TRANSCEIVER_ATTR(index)  \
	&sensor_dev_attr_module_tx_disable_##index.dev_attr.attr, \
	&sensor_dev_attr_module_rx_los_##index.dev_attr.attr,     \
	&sensor_dev_attr_module_tx_fault_##index.dev_attr.attr
	
/*reset*/
#define DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(index) \
	static SENSOR_DEVICE_ATTR(module_reset_##index, S_IWUSR | S_IRUGO, get_mode_reset, set_mode_reset, MODULE_RESET_##index)
#define DECLARE_TRANSCEIVER_RESET_ATTR(index)  &sensor_dev_attr_module_reset_##index.dev_attr.attr

/*cpld interrupt*/
#define DECLARE_CPLD_DEVICE_INTR_ATTR(index) \
	static SENSOR_DEVICE_ATTR(cpld_intr_##index, S_IRUGO, show_interrupt, NULL, CPLD_INTR_##index)
#define DECLARE_CPLD_INTR_ATTR(index)  &sensor_dev_attr_cpld_intr_##index.dev_attr.attr



static SENSOR_DEVICE_ATTR(version, S_IRUGO, show_version, NULL, CPLD_VERSION);
static SENSOR_DEVICE_ATTR(access, S_IWUSR, NULL, access, ACCESS);
/* transceiver attributes */
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(1);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(2);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(3);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(4);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(5);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(6);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(7);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(8);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(9);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(10);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(11);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(12);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(13);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(14);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(15);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(16);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(17);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(18);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(19);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(20);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(21);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(22);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(23);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(24);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(25);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(26);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(27);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(28);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(29);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(30);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(31);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(32);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(33);
DECLARE_TRANSCEIVER_PRESENT_SENSOR_DEVICE_ATTR(34);
DECLARE_SFP_TRANSCEIVER_SENSOR_DEVICE_ATTR(33);
DECLARE_SFP_TRANSCEIVER_SENSOR_DEVICE_ATTR(34);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(1);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(2);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(3);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(4);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(5);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(6);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(7);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(8);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(9);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(10);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(11);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(12);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(13);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(14);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(15);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(16);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(17);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(18);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(19);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(20);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(21);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(22);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(23);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(24);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(25);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(26);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(27);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(28);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(29);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(30);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(31);
DECLARE_TRANSCEIVER_SENSOR_DEVICE_RESET_ATTR(32);
DECLARE_CPLD_DEVICE_INTR_ATTR(1);
DECLARE_CPLD_DEVICE_INTR_ATTR(2);
DECLARE_CPLD_DEVICE_INTR_ATTR(3);
DECLARE_CPLD_DEVICE_INTR_ATTR(4);



static struct attribute *as9716_32d_fpga_attributes[] = {
    &sensor_dev_attr_version.dev_attr.attr,
    &sensor_dev_attr_access.dev_attr.attr,
	NULL
};

static const struct attribute_group as9716_32d_fpga_group = {
	.attrs = as9716_32d_fpga_attributes,
};

static struct attribute *as9716_32d_cpld1_attributes[] = {
    &sensor_dev_attr_version.dev_attr.attr,
    &sensor_dev_attr_access.dev_attr.attr,
    DECLARE_TRANSCEIVER_PRESENT_ATTR(1),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(2),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(3),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(4),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(5),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(6),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(7),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(8),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(9),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(10),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(11),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(12),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(13),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(14),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(15),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(16),
	DECLARE_TRANSCEIVER_RESET_ATTR(1),
	DECLARE_TRANSCEIVER_RESET_ATTR(2),
	DECLARE_TRANSCEIVER_RESET_ATTR(3),
	DECLARE_TRANSCEIVER_RESET_ATTR(4),
	DECLARE_TRANSCEIVER_RESET_ATTR(5),
	DECLARE_TRANSCEIVER_RESET_ATTR(6),
	DECLARE_TRANSCEIVER_RESET_ATTR(7),
	DECLARE_TRANSCEIVER_RESET_ATTR(8),
	DECLARE_TRANSCEIVER_RESET_ATTR(9),
	DECLARE_TRANSCEIVER_RESET_ATTR(10),
	DECLARE_TRANSCEIVER_RESET_ATTR(11),
	DECLARE_TRANSCEIVER_RESET_ATTR(12),
	DECLARE_TRANSCEIVER_RESET_ATTR(13),
	DECLARE_TRANSCEIVER_RESET_ATTR(14),
	DECLARE_TRANSCEIVER_RESET_ATTR(15),
	DECLARE_TRANSCEIVER_RESET_ATTR(16),
	DECLARE_CPLD_INTR_ATTR(1),
	DECLARE_CPLD_INTR_ATTR(2),
	NULL
};

static const struct attribute_group as9716_32d_cpld1_group = {
	.attrs = as9716_32d_cpld1_attributes,
};

static struct attribute *as9716_32d_cpld2_attributes[] = {
    &sensor_dev_attr_version.dev_attr.attr,
    &sensor_dev_attr_access.dev_attr.attr,	
    DECLARE_TRANSCEIVER_PRESENT_ATTR(17),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(18),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(19),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(20),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(21),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(22),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(23),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(24),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(25),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(26),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(27),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(28),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(29),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(30),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(31),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(32),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(33),
	DECLARE_TRANSCEIVER_PRESENT_ATTR(34),
    DECLARE_SFP_TRANSCEIVER_ATTR(33),
    DECLARE_SFP_TRANSCEIVER_ATTR(34),
    DECLARE_TRANSCEIVER_RESET_ATTR(17),
	DECLARE_TRANSCEIVER_RESET_ATTR(18),
	DECLARE_TRANSCEIVER_RESET_ATTR(19),
	DECLARE_TRANSCEIVER_RESET_ATTR(20),
	DECLARE_TRANSCEIVER_RESET_ATTR(21),
	DECLARE_TRANSCEIVER_RESET_ATTR(22),
	DECLARE_TRANSCEIVER_RESET_ATTR(23),
	DECLARE_TRANSCEIVER_RESET_ATTR(24),
	DECLARE_TRANSCEIVER_RESET_ATTR(25),
	DECLARE_TRANSCEIVER_RESET_ATTR(26),
	DECLARE_TRANSCEIVER_RESET_ATTR(27),
	DECLARE_TRANSCEIVER_RESET_ATTR(28),
	DECLARE_TRANSCEIVER_RESET_ATTR(29),
	DECLARE_TRANSCEIVER_RESET_ATTR(30),
	DECLARE_TRANSCEIVER_RESET_ATTR(31),
	DECLARE_TRANSCEIVER_RESET_ATTR(32),
	DECLARE_CPLD_INTR_ATTR(3),
	DECLARE_CPLD_INTR_ATTR(4),
	NULL
};

static const struct attribute_group as9716_32d_cpld2_group = {
	.attrs = as9716_32d_cpld2_attributes,
};


static  ssize_t show_interrupt(struct device *dev, struct device_attribute *da,
             char *buf)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    struct i2c_client *client = to_i2c_client(dev);
    struct as9716_32d_cpld_data *data = i2c_get_clientdata(client);
    int status = 0;
    u8 reg = 0; 
    
    switch (attr->index)
	{   
        case CPLD_INTR_1:
            reg  = 0x10;
            break;
        case CPLD_INTR_3:
            reg  = 0x10;
            break;
        case CPLD_INTR_2:
            reg  = 0x11;
            break;
        case CPLD_INTR_4:
            reg  = 0x11;
            break; 
        default:
            return -ENODEV;
    }
    mutex_lock(&data->update_lock);
    status = as9716_32d_cpld_read_internal(client, reg);
    if (unlikely(status < 0)) {
        goto exit;
    }
    mutex_unlock(&data->update_lock);

    return sprintf(buf, "0x%x\n", status);

exit:
    mutex_unlock(&data->update_lock);
    return status;
}


static ssize_t show_status(struct device *dev, struct device_attribute *da,
             char *buf)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    struct i2c_client *client = to_i2c_client(dev);
    struct as9716_32d_cpld_data *data = i2c_get_clientdata(client);
	int status = 0;
	u8 reg = 0, mask = 0, revert = 0;
    
	switch (attr->index) {
	case MODULE_PRESENT_1 ... MODULE_PRESENT_8:
		reg  = 0x12;
		mask = 0x1 << (attr->index - MODULE_PRESENT_1);
		break;
	case MODULE_PRESENT_9 ... MODULE_PRESENT_16:
		reg  = 0x13;
		mask = 0x1 << (attr->index - MODULE_PRESENT_9);
		break;
	case MODULE_PRESENT_17 ... MODULE_PRESENT_24:
		reg  = 0x12;
		mask = 0x1 << (attr->index - MODULE_PRESENT_17);
		break;
	case MODULE_PRESENT_25 ... MODULE_PRESENT_32:
		reg  = 0x13;
		mask = 0x1 << (attr->index - MODULE_PRESENT_25);
	    break;
    case MODULE_PRESENT_33:
        reg  = 0x20;
        mask = 0x1;
        break;
     case MODULE_PRESENT_34:
        reg  = 0x20;
        mask = 0x8;
        break;
    case MODULE_RXLOS_33:
        reg  = 0x20;
        mask = 0x2;
        break;
     case MODULE_RXLOS_34:
        reg  = 0x20;
        mask = 0x10;
        break;    
	case MODULE_TXDISABLE_33:
		reg  = 0x21;
		mask = 0x1;
		break;
	case MODULE_TXDISABLE_34:
		reg  = 0x21;
		mask = 0x2;
		break;	
	
	default:
		return 0;
	}

    if (attr->index >= MODULE_PRESENT_1 && attr->index <= MODULE_PRESENT_34) {
        revert = 1;
    }

    mutex_lock(&data->update_lock);
	status = as9716_32d_cpld_read_internal(client, reg);
	if (unlikely(status < 0)) {
		goto exit;
	}
	mutex_unlock(&data->update_lock);

	return sprintf(buf, "%d\n", revert ? !(status & mask) : !!(status & mask));

exit:
	mutex_unlock(&data->update_lock);
	return status;
}

static ssize_t set_tx_disable(struct device *dev, struct device_attribute *da,
			const char *buf, size_t count)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
	struct i2c_client *client = to_i2c_client(dev);
	struct as9716_32d_cpld_data *data = i2c_get_clientdata(client);
	long disable;
	int status;
    u8 reg = 0, mask = 0;
     
	status = kstrtol(buf, 10, &disable);
	if (status) {
		return status;
	}

	switch (attr->index) {
	case MODULE_TXDISABLE_33:
		reg  = 0x21;
		mask = 0x1;
		break;
	case MODULE_TXDISABLE_34:
		reg  = 0x21;
		mask = 0x2;
		break;
	default:
		return 0;
	}

    /* Read current status */
    mutex_lock(&data->update_lock);
	status = as9716_32d_cpld_read_internal(client, reg);
	if (unlikely(status < 0)) {
		goto exit;
	}

	/* Update tx_disable status */
	if (disable) {
		status |= mask;
	}
	else {
		status &= ~mask;
	}

    status = as9716_32d_cpld_write_internal(client, reg, status);
	if (unlikely(status < 0)) {
		goto exit;
	}
    
    mutex_unlock(&data->update_lock);
    return count;

exit:
	mutex_unlock(&data->update_lock);
	return status;
}

static ssize_t access(struct device *dev, struct device_attribute *da,
			const char *buf, size_t count)
{
	int status;
	u32 addr, val;
    struct i2c_client *client = to_i2c_client(dev);
    struct as9716_32d_cpld_data *data = i2c_get_clientdata(client);
    
	if (sscanf(buf, "0x%x 0x%x", &addr, &val) != 2) {
		return -EINVAL;
	}

	if (addr > 0xFF || val > 0xFF) {
		return -EINVAL;
	}

	mutex_lock(&data->update_lock);
	status = as9716_32d_cpld_write_internal(client, addr, val);
	if (unlikely(status < 0)) {
		goto exit;
	}
	mutex_unlock(&data->update_lock);
	return count;

exit:
	mutex_unlock(&data->update_lock);
	return status;
}

static void as9716_32d_cpld_add_client(struct i2c_client *client)
{
    struct cpld_client_node *node = kzalloc(sizeof(struct cpld_client_node), GFP_KERNEL);

    if (!node) {
        dev_dbg(&client->dev, "Can't allocate cpld_client_node (0x%x)\n", client->addr);
        return;
    }

    node->client = client;

	mutex_lock(&list_lock);
    list_add(&node->list, &cpld_client_list);
	mutex_unlock(&list_lock);
}

static void as9716_32d_cpld_remove_client(struct i2c_client *client)
{
    struct list_head    *list_node = NULL;
    struct cpld_client_node *cpld_node = NULL;
    int found = 0;

	mutex_lock(&list_lock);

    list_for_each(list_node, &cpld_client_list)
    {
        cpld_node = list_entry(list_node, struct cpld_client_node, list);

        if (cpld_node->client == client) {
            found = 1;
            break;
        }
    }

    if (found) {
        list_del(list_node);
        kfree(cpld_node);
    }

	mutex_unlock(&list_lock);
}

static ssize_t show_version(struct device *dev, struct device_attribute *attr, char *buf)
{
    int val = 0;
    struct i2c_client *client = to_i2c_client(dev);
	
	val = i2c_smbus_read_byte_data(client, 0x1);

    if (val < 0) {
        dev_dbg(&client->dev, "cpld(0x%x) reg(0x1) err %d\n", client->addr, val);
    }
	
    return sprintf(buf, "%d\n", val);
}

static ssize_t get_mode_reset(struct device *dev, struct device_attribute *da,
			char *buf)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    struct i2c_client *client = to_i2c_client(dev);
    struct as9716_32d_cpld_data *data = i2c_get_clientdata(client);
	int status = 0;
	u8 reg = 0, mask = 0;
    
	switch (attr->index) {
	case MODULE_RESET_1 ... MODULE_RESET_8:
		reg  = 0x14;
		mask = 0x1 << (attr->index - MODULE_RESET_1);
		break;
	case MODULE_RESET_9 ... MODULE_RESET_16:
		reg  = 0x15;
		mask = 0x1 << (attr->index - MODULE_RESET_9);
		break;
	case MODULE_RESET_17 ... MODULE_RESET_24:
		reg  = 0x14;
		mask = 0x1 << (attr->index - MODULE_RESET_17);
		break;
	case MODULE_RESET_25 ... MODULE_RESET_32:
		reg  = 0x15;
		mask = 0x1 << (attr->index - MODULE_RESET_25);
		break;
	default:
		return 0;
	}
	

    mutex_lock(&data->update_lock);
	status = as9716_32d_cpld_read_internal(client, reg);
	
	if (unlikely(status < 0)) {
		goto exit;
	}
	mutex_unlock(&data->update_lock);

	return sprintf(buf, "%d\r\n", !(status & mask));
	
exit:
	mutex_unlock(&data->update_lock);
	return status;	
}

static ssize_t set_mode_reset(struct device *dev, struct device_attribute *da,
			const char *buf, size_t count)
{    
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    struct i2c_client *client = to_i2c_client(dev);
    struct as9716_32d_cpld_data *data = i2c_get_clientdata(client);
    long reset;
    int status=0, val, error;
	u8 reg = 0, mask = 0;
	

    error = kstrtol(buf, 10, &reset);
    if (error) {
        return error;
    }
    
    switch (attr->index) {
	case MODULE_RESET_1 ... MODULE_RESET_8:
		reg  = 0x14;
		mask = 0x1 << (attr->index - MODULE_RESET_1);
		break;
	case MODULE_RESET_9 ... MODULE_RESET_16:
		reg  = 0x15;
		mask = 0x1 << (attr->index - MODULE_RESET_9);
		break;
	case MODULE_RESET_17 ... MODULE_RESET_24:
		reg  = 0x14;
		mask = 0x1 << (attr->index - MODULE_RESET_17);
		break;
	case MODULE_RESET_25 ... MODULE_RESET_32:
		reg  = 0x15;
		mask = 0x1 << (attr->index - MODULE_RESET_25);
		break;
	default:
		return 0;
	}
	mutex_lock(&data->update_lock);
	
	status = as9716_32d_cpld_read_internal(client, reg);
	if (unlikely(status < 0)) {
		goto exit;
	}
	
	/* Update lp_mode status */
    if (reset)
    {       
        val = status&(~mask);
    }
    else
    {       
        val =status | (mask);
    }
	
	status = as9716_32d_cpld_write_internal(client, reg, val);
	if (unlikely(status < 0)) {
		goto exit;
	}
	mutex_unlock(&data->update_lock);
	return count;

exit:
	mutex_unlock(&data->update_lock);
	return status;
}



/*
 * I2C init/probing/exit functions
 */
static int as9716_32d_cpld_probe(struct i2c_client *client)
{
	struct i2c_adapter *adap = to_i2c_adapter(client->dev.parent);
	struct as9716_32d_cpld_data *data;
	int ret = -ENODEV;
	int status;	
	const struct attribute_group *group = NULL;
	const struct i2c_device_id *id;

	if (!i2c_check_functionality(adap, I2C_FUNC_SMBUS_BYTE))
		goto exit;

	data = kzalloc(sizeof(struct as9716_32d_cpld_data), GFP_KERNEL);
	if (!data) {
		ret = -ENOMEM;
		goto exit;
	}

	id = i2c_match_id(as9716_32d_cpld_id, client);

	i2c_set_clientdata(client, data);
    mutex_init(&data->update_lock);
	data->type = id->driver_data;

   
    /* Register sysfs hooks */
    switch (data->type) {
    case as9716_32d_fpga:
        group = &as9716_32d_fpga_group;
        break;
    case as9716_32d_cpld1:
        group = &as9716_32d_cpld1_group;
        /*Set interrupt mask to 0, and then can get intr from 0x8*/
        status=as9716_32d_cpld_write_internal(client, 0x9, 0x0); 
        if (status < 0)
        {
           dev_dbg(&client->dev, "cpld1 reg 0x9 err %d\n", status);            
        } 
        break;
    case as9716_32d_cpld2:
        group = &as9716_32d_cpld2_group;
        /*Set interrupt mask to 0, and then can get intr from 0x8*/
        status=as9716_32d_cpld_write_internal(client, 0x9, 0x0); 
        if (status < 0)
        {
           dev_dbg(&client->dev, "cpld2 reg 0x65 err %d\n", status);            
        } 
         break; 
     case as9716_32d_cpld_cpu:
         /* Disable CPLD reset to avoid DUT will be reset.
          */
         status=as9716_32d_cpld_write_internal(client, 0x3, 0x0); 
         if (status < 0)
         {
            dev_dbg(&client->dev, "cpu_cpld reg 0x65 err %d\n", status);            
         }      
    default:
        break;
    }

    if (group) {
        ret = sysfs_create_group(&client->dev.kobj, group);
        if (ret) {
            goto exit_free;
        }
    }

    as9716_32d_cpld_add_client(client);
    return 0;

exit_free:
    kfree(data);
exit:
	return ret;
}

static void as9716_32d_cpld_remove(struct i2c_client *client)
{
    struct as9716_32d_cpld_data *data = i2c_get_clientdata(client);
    const struct attribute_group *group = NULL;

    as9716_32d_cpld_remove_client(client);

    /* Remove sysfs hooks */
    switch (data->type) {
    case as9716_32d_fpga:
        group = &as9716_32d_fpga_group;
        break;
    case as9716_32d_cpld1:
        group = &as9716_32d_cpld1_group;
        break;
    case as9716_32d_cpld2:
        group = &as9716_32d_cpld2_group;
        break;
    default:
        break;
    }

    if (group) {
        sysfs_remove_group(&client->dev.kobj, group);
    }

    kfree(data);

}

static int as9716_32d_cpld_read_internal(struct i2c_client *client, u8 reg)
{
	int status = 0, retry = I2C_RW_RETRY_COUNT;

	while (retry) {
		status = i2c_smbus_read_byte_data(client, reg);
		if (unlikely(status < 0)) {
			msleep(I2C_RW_RETRY_INTERVAL);
			retry--;
			continue;
		}

		break;
	}

    return status;
}

static int as9716_32d_cpld_write_internal(struct i2c_client *client, u8 reg, u8 value)
{
	int status = 0, retry = I2C_RW_RETRY_COUNT;
    
	while (retry) {
		status = i2c_smbus_write_byte_data(client, reg, value);
		if (unlikely(status < 0)) {
			msleep(I2C_RW_RETRY_INTERVAL);
			retry--;
			continue;
		}

		break;
	}

    return status;
}

int as9716_32d_cpld_read(unsigned short cpld_addr, u8 reg)
{
    struct list_head   *list_node = NULL;
    struct cpld_client_node *cpld_node = NULL;
    int ret = -EPERM;

    mutex_lock(&list_lock);

    list_for_each(list_node, &cpld_client_list)
    {
        cpld_node = list_entry(list_node, struct cpld_client_node, list);

        if (cpld_node->client->addr == cpld_addr) {
            ret = as9716_32d_cpld_read_internal(cpld_node->client, reg);
    		break;
        }
    }

	mutex_unlock(&list_lock);

    return ret;
}
EXPORT_SYMBOL(as9716_32d_cpld_read);

int as9716_32d_cpld_write(unsigned short cpld_addr, u8 reg, u8 value)
{
    struct list_head   *list_node = NULL;
    struct cpld_client_node *cpld_node = NULL;
    int ret = -EIO;
    
	mutex_lock(&list_lock);

    list_for_each(list_node, &cpld_client_list)
    {
        cpld_node = list_entry(list_node, struct cpld_client_node, list);

        if (cpld_node->client->addr == cpld_addr) {
            ret = as9716_32d_cpld_write_internal(cpld_node->client, reg, value);
            break;
        }
    }

	mutex_unlock(&list_lock);

    return ret;
}
EXPORT_SYMBOL(as9716_32d_cpld_write);

static struct i2c_driver as9716_32d_cpld_driver = {
	.driver		= {
		.name	= "as9716_32d_cpld",
		.owner	= THIS_MODULE,
	},
	.probe		= as9716_32d_cpld_probe,
	.remove		= as9716_32d_cpld_remove,
	.id_table	= as9716_32d_cpld_id,
};

static int __init as9716_32d_cpld_init(void)
{
    mutex_init(&list_lock);
    return i2c_add_driver(&as9716_32d_cpld_driver);
}

static void __exit as9716_32d_cpld_exit(void)
{
    i2c_del_driver(&as9716_32d_cpld_driver);
}

MODULE_AUTHOR("Jostar Yang <jostar_yang@accton.com>");
MODULE_DESCRIPTION("Accton I2C CPLD driver");
MODULE_LICENSE("GPL");

module_init(as9716_32d_cpld_init);
module_exit(as9716_32d_cpld_exit);

