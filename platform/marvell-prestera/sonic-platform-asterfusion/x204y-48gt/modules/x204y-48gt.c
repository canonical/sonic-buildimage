/* An hwmon driver for Asterfusion X204Y-48GT-M CPLD I2C Module */
#pragma GCC diagnostic ignored "-Wformat-zero-length"
#include "x204y-48gt.h"

/* Addresses scanned */
static const unsigned short normal_i2c[] = { 0x30, I2C_CLIENT_END };


/* i2c-0 function */

static ssize_t cpld_byte_get(struct device *dev, struct device_attribute *da, char *buf)
{
    u32 status = -EPERM;
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    sprintf(buf, "");

    if (CPLD_VER == attr->index || BOARD_VER == attr->index)
    {
        status = i2c_smbus_read_byte_data(x204y_48gt_i2c_client, attr->index);
    }

    if (CPLD_VER == attr->index)
    {
        sprintf(buf, "%sCPLD version", buf);
    }
    else if (BOARD_VER == attr->index)
    {
       sprintf(buf, "%sBoard version", buf);
    }
    return sprintf(buf, "%s is %02x\n", buf, status);
}

static ssize_t sfp_status_get(struct device *dev, struct device_attribute *da, char *buf)
{
    u32 status = -EPERM;
    u8 port_num = 49;
    u8 i;
    u8 mask = 0x1;
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);

    status = i2c_smbus_read_byte_data(x204y_48gt_i2c_client, attr->index);

    sprintf(buf, "");
    switch(attr->index)
    {
        case SFP_TX_FAULT:
        {
            for (i = 0; i < 4; i++)
            {
                if (status & mask)
                {
                    sprintf(buf, "%sSFP %02d Tx failed\n", buf, port_num);
                }
                else
                {
                    sprintf(buf, "%sSFP %02d Tx ok\n", buf, port_num);
                }
                port_num++;
                mask = mask << 1;
            }
        }
        break;

        case SFP_PRESENT:
        {
            for (i = 0; i < 4; i++)
            {
                if (status & mask)
                {
                    sprintf(buf, "%sSFP %02d is not present\n", buf, port_num);
                }
                else
                {
                    sprintf(buf, "%sSFP %02d is present\n", buf, port_num);
                }
                port_num++;
                mask = mask << 1;
            }
        }
        break;

        case SFP_RX_LOSS:
        {
            for (i = 0; i < 4; i++)
            {
                if (status & mask)
                {
                    sprintf(buf, "%sSFP %02d loss of signal\n", buf, port_num);
                }
                else
                {
                    sprintf(buf, "%sSFP %02d signal detected\n", buf, port_num);
                }
                port_num++;
                mask = mask << 1;
            }
        }
        break;

        case SFP_TX_STAT:
        {
            for (i = 0; i < 4; i++)
            {
                if (status & mask)
                {
                    sprintf(buf, "%sSFP %02d Disable TX\n", buf, port_num);
                }
                else
                {
                    sprintf(buf, "%sSFP %02d Enable TX\n", buf, port_num);
                }
                port_num++;
                mask = mask << 1;
            }
        }

        break;
    }
    return sprintf(buf, "%s\n", buf);
}
static ssize_t sfp_tx_get(struct device *dev, struct device_attribute *da, char *buf)
{
    u32 status = -EPERM;
    u8 value = -EPERM;
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);

    status = i2c_smbus_read_byte_data(x204y_48gt_i2c_client, SFP_TX_STAT);
    GET_BIT(status, attr->index, value);

    sprintf(buf, "");
    switch(attr->index)
    {
        case SFP52_BIT:
        sprintf(buf, "%sSFP52 tx_disable =  0x%x\n", buf, value);
        break;
        case SFP51_BIT:
        sprintf(buf, "%sSFP51 tx_disable =  0x%x\n", buf, value);
        break;
        case SFP50_BIT:
        sprintf(buf, "%sSFP50 tx_disable =  0x%x\n", buf, value);
        break;
        case SFP49_BIT:
        sprintf(buf, "%sSFP49 tx_disable =  0x%x\n", buf, value);
        break;
    }
    return sprintf(buf, "%s\n", buf);
}
static ssize_t sfp_tx_set(struct device *dev, struct device_attribute *da, const char *buf, size_t count)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);

    u32 status = -EPERM;
    u16 val = simple_strtol(buf, NULL, 10);

    status = i2c_smbus_read_byte_data(x204y_48gt_i2c_client, SFP_TX_STAT);
 
    if(val)
        SET_BIT(status, (attr->index % (SFP52_BIT + 1)));
    else
        CLEAR_BIT(status, (attr->index % (SFP52_BIT + 1)));

    status = i2c_smbus_write_byte_data(x204y_48gt_i2c_client, SFP_TX_STAT, status);
    return count;
}

static ssize_t sys_adc_status_get(struct device *dev, struct device_attribute *da, char *buf)
{
    u32 status = -EPERM;
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    u8 i;
    u16 dc_status [8] = {0};
    u8 mask = 0x1;

    sprintf(buf, "");
    if (attr->index == ADC_STAT)
    {
        status = i2c_smbus_read_byte_data(x204y_48gt_i2c_client, attr->index);
        for (i = 0; i < 8; i++)
        {
            dc_status[i] = status & mask;
            mask = mask << 1;
        }
        sprintf(buf, "%svdd_core_0v8_pg is %s\n", buf, dc_status[0]?"normal":"abnormal");
        sprintf(buf, "%svcc3v3_pg       is %s\n", buf, dc_status[1]?"normal":"abnormal");
        sprintf(buf, "%svcc1v2_pg       is %s\n", buf, dc_status[2]?"normal":"abnormal");
        sprintf(buf, "%svcc1v15_pg      is %s\n", buf, dc_status[3]?"normal":"abnormal");
        sprintf(buf, "%svcc1v5_pg       is %s\n", buf, dc_status[4]?"normal":"abnormal");
        sprintf(buf, "%svcc2v5_pg       is %s\n", buf, dc_status[5]?"normal":"abnormal");
        sprintf(buf, "%svcc5v_pg        is %s\n", buf, dc_status[6]?"normal":"abnormal");
        sprintf(buf, "%svtt_ddr_pg      is %s\n", buf, dc_status[7]?"normal":"abnormal");
    }
    return sprintf(buf, "%s\n", buf);
}
static ssize_t rst_ctl_get(struct device *dev, struct device_attribute *da, char *buf)
{
    u32 status = -EPERM;
    u8 value = -EPERM;
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);

    status = i2c_smbus_read_byte_data(x204y_48gt_i2c_client, RST_CTL);
    GET_BIT(status, attr->index, value);

    sprintf(buf, "");
    switch(attr->index)
    {
        case PCA9548_CTL_BIT:
        sprintf(buf, "%sRESET_PCA9548 status =  0x%x\n", buf, value);
        break;
        case PHY6_CTL_BIT:
        sprintf(buf, "%sRESET_PHY6 status =  0x%x\n", buf, value);
        break;
        case PHY5_CTL_BIT:
        sprintf(buf, "%sRESET_PHY5 status =  0x%x\n", buf, value);
        break;
        case PHY4_CTL_BIT:
        sprintf(buf, "%sRESET_PHY4 status =  0x%x\n", buf, value);
        break;
        case PHY3_CTL_BIT:
        sprintf(buf, "%sRESET_PHY3 status =  0x%x\n", buf, value);
        break;
        case PHY2_CTL_BIT:
        sprintf(buf, "%sRESET_PHY2 status =  0x%x\n", buf, value);
        break;
        case PHY1_CTL_BIT:
        sprintf(buf, "%sRESET_PHY1 status =  0x%x\n", buf, value);
        break;
    }
    return sprintf(buf, "%s\n", buf);
}
static ssize_t rst_ctl_set(struct device *dev, struct device_attribute *da, const char *buf, size_t count)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);

    u32 status = -EPERM;
    u16 val = simple_strtol(buf, NULL, 10);

    status = i2c_smbus_read_byte_data(x204y_48gt_i2c_client, RST_CTL);
 
    if(val)
        SET_BIT(status, (attr->index % 8));
    else
        CLEAR_BIT(status, (attr->index % 8));

    status = i2c_smbus_write_byte_data(x204y_48gt_i2c_client, RST_CTL, status);
    return count;
}
static ssize_t cpld_ctrl1_get(struct device *dev, struct device_attribute *da, char *buf)
{
    u32 status = -EPERM;
    u8 value = -EPERM;
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);

    status = i2c_smbus_read_byte_data(x204y_48gt_i2c_client, CPLD_CTL1);
    GET_BIT(status, attr->index, value);

    sprintf(buf, "");
    switch(attr->index)
    {
        case EEPROM_WP_CTRL_BIT:
        sprintf(buf, "%sEEPROM_WP status =  0x%x\n", buf, value);
        break;
        case OVER_TEMP_CTRL_BIT:
        sprintf(buf, "%sOVER_TEMP status =  0x%x\n", buf, value);
        break;
        case WDT_CTRL_BIT:
        sprintf(buf, "%sWDT status =  0x%x\n", buf, value);
        break;
    }
    return sprintf(buf, "%s\n", buf);
}
static ssize_t cpld_ctrl1_set(struct device *dev, struct device_attribute *da, const char *buf, size_t count)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);

    u32 status = -EPERM;
    u16 val = simple_strtol(buf, NULL, 10);

    status = i2c_smbus_read_byte_data(x204y_48gt_i2c_client, CPLD_CTL1);
 
    if(val)
        SET_BIT(status, (attr->index % 8));
    else
        CLEAR_BIT(status, (attr->index % 8));

    status = i2c_smbus_write_byte_data(x204y_48gt_i2c_client, CPLD_CTL1, status);
    return count;
}
static ssize_t fan_rpm_get(struct device *dev, struct device_attribute *da, char *buf)
{
    u32 status = -EPERM;

    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    sprintf(buf, "");

    if (FAN1_OUTLET_RPM == attr->index || FAN2_OUTLET_RPM == attr->index || FAN3_OUTLET_RPM == attr->index)
    {
        status = i2c_smbus_read_byte_data(x204y_48gt_i2c_client, attr->index);
        sprintf(buf, "%s%d", buf, status);
    }
    return sprintf(buf, "%s\n", buf);
}
static ssize_t fan_stat_get(struct device *dev, struct device_attribute *da, char *buf)
{
    u32 status = -EPERM;
    u8 value = -EPERM;
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    sprintf(buf, "");

    status = i2c_smbus_read_byte_data(x204y_48gt_i2c_client, FAN_STAT);
    GET_BIT(status, attr->index, value);

    return sprintf(buf, "%s%d\n", buf, value);
}
static ssize_t fan_mode_get(struct device *dev, struct device_attribute *da, char *buf)
{
    u32 status = -EPERM;
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    sprintf(buf, "");

    if (FAN_CTL1 == attr->index)
    {
        status = i2c_smbus_read_byte_data(x204y_48gt_i2c_client, attr->index);
        sprintf(buf, "%s%d", buf, status & 0x1);
    }

    return sprintf(buf, "%s\n", buf);
}
static ssize_t fan_mode_set(struct device *dev, struct device_attribute *da, const char *buf, size_t count)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);

    u32 status = -EPERM;
    u16 val = simple_strtol(buf, NULL, 10);

    if (FAN_CTL1 == attr->index)
    {
        status = i2c_smbus_write_byte_data(x204y_48gt_i2c_client, attr->index, val & 0x1);
    }

    return count;
}
static ssize_t fan_speed_get(struct device *dev, struct device_attribute *da, char *buf)
{
    u32 status = -EPERM;
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    sprintf(buf, "");

    if (FAN_CTL2 == attr->index)
    {
        status = i2c_smbus_read_byte_data(x204y_48gt_i2c_client, attr->index);
        sprintf(buf, "%sfan_mode_level is %d", buf, status % 8);
    }

    return sprintf(buf, "%s\n", buf);
}
static ssize_t fan_speed_set(struct device *dev, struct device_attribute *da, const char *buf, size_t count)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);

    u32 status = -EPERM;
    u16 val = simple_strtol(buf, NULL, 10);

    if (FAN_CTL2 == attr->index)
    {
        status = i2c_smbus_write_byte_data(x204y_48gt_i2c_client, attr->index, val % 8);
    }

    return count;
}
static ssize_t themal_temp_get(struct device *dev, struct device_attribute *da, char *buf)
{
    u32 status = -EPERM;
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    sprintf(buf, "");

    if (AC5X_LM75 == attr->index)
    {
        status = i2c_smbus_read_byte_data(x204y_48gt_i2c_client, attr->index);
        sprintf(buf, "%s%d", buf, status);
    }

    return sprintf(buf, "%s\n", buf);  
}

static ssize_t sys_led_ctrl_get(struct device *dev, struct device_attribute *da, char *buf)
{
    u8 status = -EPERM;

    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    
    sprintf(buf, "SYS LED is set to: ");
    if (SYS_LED == attr->index)
    {
        status = i2c_smbus_read_byte_data(x204y_48gt_i2c_client, SYS_LED); //to get register 0x30 0x13
        status &= 0x1;
        debug_print((KERN_DEBUG "DEBUG : sys_led_ctrl_get led status = %x\n",status));

        if(status == LED_GREEN_BLINK)
        {
            sprintf(buf, "%sgreen and blink\n", buf);
        }
        else if(status == LED_GREEN)
        {
            sprintf(buf, "%sgreen\n", buf);
        }
    }

    return sprintf(buf, "%s", buf);
}
static ssize_t sys_led_ctrl_set(struct device *dev, struct device_attribute *da, const char *buf, size_t count)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);

    u32 status = -EPERM;
    u16 val = simple_strtol(buf, NULL, 10);

    if (SYS_LED == attr->index)
    {
        status = i2c_smbus_write_byte_data(x204y_48gt_i2c_client, attr->index, val & 0x1);
    }
    return count;
}
static ssize_t loc_led_ctrl_get(struct device *dev, struct device_attribute *da, char *buf)
{
    u8 status = -EPERM;

    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    
    sprintf(buf, "LOC LED is set to: ");
    if (LOC_LED == attr->index)
    {
        status = i2c_smbus_read_byte_data(x204y_48gt_i2c_client, LOC_LED); //to get register 0x30 0x13
        status &= 0x1;
        debug_print((KERN_DEBUG "DEBUG : loc_led_ctrl_get led status = %x\n",status));

        if(status == 0)
        {
            sprintf(buf, "%soff\n", buf);
        }
        else if(status == 1)
        {
            sprintf(buf, "%son\n", buf);
        }
    }

    return sprintf(buf, "%s", buf);
}
static ssize_t loc_led_ctrl_set(struct device *dev, struct device_attribute *da, const char *buf, size_t count)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);

    u32 status = -EPERM;
    u16 val = simple_strtol(buf, NULL, 10);

    if (LOC_LED == attr->index)
    {
        status = i2c_smbus_write_byte_data(x204y_48gt_i2c_client, attr->index, val & 0x1);
    }
    return count;
}

static ssize_t hw_reset_get(struct device *dev, struct device_attribute *da, char *buf)
{
    u8 status = -EPERM;

    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    
    sprintf(buf, "LOC LED is set to: ");
    if (HW_RESET == attr->index)
    {
        status = i2c_smbus_read_byte_data(x204y_48gt_i2c_client, HW_RESET); //to get register 0x30 0x13
        status &= 0x1;
        debug_print((KERN_DEBUG "DEBUG : HW_RESET is %x\n",status));

        if(status == 0)
        {
            sprintf(buf, "%sset\n", buf);
        }
        else if(status == 1)
        {
            sprintf(buf, "%snot set\n", buf);
        }
    }

    return sprintf(buf, "%s", buf);
}
static ssize_t hw_reset_set(struct device *dev, struct device_attribute *da, const char *buf, size_t count)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);

    u32 status = -EPERM;
    u16 val = simple_strtol(buf, NULL, 10);

    if (HW_RESET == attr->index)
    {
        status = i2c_smbus_write_byte_data(x204y_48gt_i2c_client, attr->index, val & 0x1);
    }
    return count;
}

/* end of function */




static int Asterfusion_i2c_probe(struct i2c_client *client, const struct i2c_device_id *dev_id)
{
    struct Asterfusion_i2c_data *data;
    int status;
    if (!i2c_check_functionality(client->adapter, I2C_FUNC_SMBUS_BYTE_DATA | I2C_FUNC_SMBUS_WORD_DATA))
    {
        status = -EIO;
        goto exit;
    }
    data = kzalloc(sizeof(struct Asterfusion_i2c_data), GFP_KERNEL);
    if (!data)
    {
        printk(KERN_ALERT "kzalloc fail\n");
        status = -ENOMEM;
        goto exit;
    }
 

    i2c_set_clientdata(client, data);

    data->valid = 0;
    mutex_init(&data->update_lock);
    dev_info(&client->dev, "chip found\n");

    /* Register sysfs hooks */
    status = sysfs_create_group(&client->dev.kobj, &X204Y_48GT_SYS_group);
    if (status)
    {
        goto exit_free;
    }
    status = sysfs_create_group(&client->dev.kobj, &X204Y_48GT_Reset_group);
    if (status)
    {
        goto exit_free;
    }
    status = sysfs_create_group(&client->dev.kobj, &X204Y_48GT_Sensor_group);
    if (status)
    {
        goto exit_free;
    }
    status = sysfs_create_group(&client->dev.kobj, &X204Y_48GT_Led_group);
    if (status)
    {
        goto exit_free;
    }
    status = sysfs_create_group(&client->dev.kobj, &X204Y_48GT_SFP_group);
    if (status)
    {
        goto exit_free;
    }
    status = sysfs_create_group(&client->dev.kobj, &X204Y_48GT_FAN_group);
    if (status)
    {
        goto exit_free;
    }

    data->hwmon_dev = hwmon_device_register(&client->dev);
    if (IS_ERR(data->hwmon_dev))
    {
        status = PTR_ERR(data->hwmon_dev);
        goto exit_remove;
    }
    dev_info(&client->dev, "%s: '%s'\n", dev_name(data->hwmon_dev), client->name);

    return 0;
exit_remove:
    sysfs_remove_group(&client->dev.kobj, &X204Y_48GT_SYS_group);
    sysfs_remove_group(&client->dev.kobj, &X204Y_48GT_Reset_group);
    sysfs_remove_group(&client->dev.kobj, &X204Y_48GT_Sensor_group);
    sysfs_remove_group(&client->dev.kobj, &X204Y_48GT_Led_group);
    sysfs_remove_group(&client->dev.kobj, &X204Y_48GT_SFP_group);
    sysfs_remove_group(&client->dev.kobj, &X204Y_48GT_FAN_group);

exit_free:
    kfree(data);
exit:
    return status;
}

static int Asterfusion_i2c_remove(struct i2c_client *client)
{
    struct Asterfusion_i2c_data *data = i2c_get_clientdata(client);
    hwmon_device_unregister(data->hwmon_dev);
    sysfs_remove_group(&client->dev.kobj, &X204Y_48GT_SYS_group);
    sysfs_remove_group(&client->dev.kobj, &X204Y_48GT_Reset_group);
    sysfs_remove_group(&client->dev.kobj, &X204Y_48GT_Sensor_group);
    sysfs_remove_group(&client->dev.kobj, &X204Y_48GT_Led_group);
    sysfs_remove_group(&client->dev.kobj, &X204Y_48GT_SFP_group);
    sysfs_remove_group(&client->dev.kobj, &X204Y_48GT_FAN_group);

    kfree(data);
    return 0;
}

static const struct i2c_device_id Asterfusion_i2c_id[] =
{
    { "x204y_48gt", 0 },
    {},
};

MODULE_DEVICE_TABLE(i2c, Asterfusion_i2c_id);
static struct i2c_driver Asterfusion_i2c_driver =
{
    .class        = I2C_CLASS_HWMON,
    .driver =
    {
        .name     = "x204y_48gt",
    },
    .probe        = Asterfusion_i2c_probe,
    .remove       = Asterfusion_i2c_remove,
    .id_table     = Asterfusion_i2c_id,
    .address_list = normal_i2c,
};

static struct i2c_board_info X204Y_48GT_i2c_info[] __initdata =
{
    {
        I2C_BOARD_INFO("x204y_48gt", 0x40),
        .platform_data = NULL,
    },
};

static int __init Asterfusion_i2c_init(void)
{
    struct i2c_adapter *i2c_adap;
    i2c_adap = i2c_get_adapter(6);

    x204y_48gt_i2c_client = i2c_new_client_device(i2c_adap, &X204Y_48GT_i2c_info[0]);
    if (x204y_48gt_i2c_client == NULL)
    {
        printk("ERROR: x204y_48gt_i2c_client FAILED!\n");
        return -1;
    }
    return i2c_add_driver(&Asterfusion_i2c_driver);
}

static void __exit Asterfusion_i2c_exit(void)
{
    i2c_unregister_device(x204y_48gt_i2c_client);
    i2c_del_driver(&Asterfusion_i2c_driver);
}

MODULE_AUTHOR("Asterfusion Inc.");
MODULE_DESCRIPTION("Asterfusion X204Y-48GT-M i2c Driver");
MODULE_LICENSE("GPL");

module_init(Asterfusion_i2c_init);
module_exit(Asterfusion_i2c_exit);

