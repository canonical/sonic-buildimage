/*
 * Copyright 2019 Broadcom.
 * The term “Broadcom” refers to Broadcom Inc. and/or its subsidiaries.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 *
 * Description of various APIs related to transciever component
 */

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/jiffies.h>
#include <linux/i2c.h>
#include <linux/hwmon.h>
#include <linux/hwmon-sysfs.h>
#include <linux/err.h>
#include <linux/mutex.h>
#include <linux/sysfs.h>
#include <linux/slab.h>
#include <linux/delay.h>
#include <linux/dmi.h>
#include <linux/kobject.h>
#include "pddf_xcvr_defs.h"

/*#define SFP_DEBUG*/
#ifdef SFP_DEBUG
#define sfp_dbg(...) printk(__VA_ARGS__)
#else
#define sfp_dbg(...)
#endif

extern XCVR_SYSFS_ATTR_OPS xcvr_ops[];

int get_xcvr_module_attr_data(struct i2c_client *client, struct device *dev,
                            struct device_attribute *da, XCVR_ATTR *xattr);

int sonic_i2c_get_mod_pres(struct i2c_client *client, XCVR_ATTR *info, struct xcvr_data *data)
{
    int status = 0;
    uint32_t modpres = 0;

    if (strcmp(info->devtype, "cpld") == 0)
    {
        status = board_i2c_cpld_read(info->devaddr , info->offset);
        /*sfp_dbg(KERN_ERR "%s: status 0x%x\n", __FUNCTION__, status);*/

        if (status < 0)
            return status;
        else
        {
            modpres = ((status & BIT_INDEX(info->mask)) == info->cmpval) ? 1 : 0;
            sfp_dbg(KERN_INFO "\nMod presence :0x%x, reg_value = 0x%x, devaddr=0x%x, mask=0x%x, offset=0x%x\n", modpres, status, info->devaddr, info->mask, info->offset);
        }
    }
    else if(strcmp(info->devtype, "eeprom") == 0)
    {
        /* get client client for eeprom -  Not Applicable */
    }
    data->modpres = modpres;

    return 0;
}

int sonic_i2c_get_mod_reset(struct i2c_client *client, XCVR_ATTR *info, struct xcvr_data *data)
{
    int status = 0;
    uint32_t modreset=0;

    if (strcmp(info->devtype, "cpld") == 0)
    {
        status = board_i2c_cpld_read(info->devaddr , info->offset);
        if (status < 0)
            return status;
        else
        {
            modreset = ((status & BIT_INDEX(info->mask)) == info->cmpval) ? 1 : 0;
            sfp_dbg(KERN_INFO "\nMod Reset :0x%x, reg_value = 0x%x\n", modreset, status);
        }
    } 
    else if(strcmp(info->devtype, "eeprom") == 0)
    {
        /* get client client for eeprom -  Not Applicable */
    }

    data->reset = modreset;
    return 0;
}


int sonic_i2c_get_mod_intr_status(struct i2c_client *client, XCVR_ATTR *info, struct xcvr_data *data)
{
    int status = 0;
    uint32_t mod_intr = 0;

    if (strcmp(info->devtype, "cpld") == 0)
    {
        status = board_i2c_cpld_read(info->devaddr , info->offset);
        if (status < 0)
            return status;
        else
        {
            mod_intr = ((status & BIT_INDEX(info->mask)) == info->cmpval) ? 1 : 0;
            sfp_dbg(KERN_INFO "\nModule Interrupt :0x%x, reg_value = 0x%x\n", mod_intr, status);
        }
    } 
    else if(strcmp(info->devtype, "eeprom") == 0)
    {
        /* get client client for eeprom -  Not Applicable */
    }

    data->intr_status = mod_intr;
    return 0;
}


int sonic_i2c_get_mod_lpmode(struct i2c_client *client, XCVR_ATTR *info, struct xcvr_data *data)
{
    int status = 0;
    uint32_t lpmode = 0;

    if (strcmp(info->devtype, "cpld") == 0)
    {
        status = board_i2c_cpld_read(info->devaddr , info->offset);
        if (status < 0)
            return status;
        else
        {
            lpmode = ((status & BIT_INDEX(info->mask)) == info->cmpval) ? 1 : 0;
            sfp_dbg(KERN_INFO "\nModule LPmode :0x%x, reg_value = 0x%x\n", lpmode, status);
        }
    }
    
    data->lpmode = lpmode;
    return 0;
}

int sonic_i2c_get_mod_rxlos(struct i2c_client *client, XCVR_ATTR *info, struct xcvr_data *data)
{
    int status = 0;
    uint32_t rxlos = 0;


    if (strcmp(info->devtype, "cpld") == 0)
    {
        status = board_i2c_cpld_read(info->devaddr , info->offset);
        if (status < 0)
            return status;
        else
        {
            rxlos = ((status & BIT_INDEX(info->mask)) == info->cmpval) ? 1 : 0;
            sfp_dbg(KERN_INFO "\nModule RxLOS :0x%x, reg_value = 0x%x\n", rxlos, status);
        }
    } 
    data->rxlos = rxlos;

    return 0;
}

int sonic_i2c_get_mod_txdisable(struct i2c_client *client, XCVR_ATTR *info, struct xcvr_data *data)
{
    int status = 0;
    uint32_t txdis = 0;

    if (strcmp(info->devtype, "cpld") == 0)
    {
        status = board_i2c_cpld_read(info->devaddr , info->offset);
        if (status < 0)
            return status;
        else
        {
            txdis = ((status & BIT_INDEX(info->mask)) == info->cmpval) ? 1 : 0;
            sfp_dbg(KERN_INFO "\nModule TxDisable :0x%x, reg_value = 0x%x\n", txdis, status);
        }
    }
    data->txdisable = txdis;

    return 0;
}

int sonic_i2c_get_mod_txfault(struct i2c_client *client, XCVR_ATTR *info, struct xcvr_data *data)
{
    int status = 0;
    uint32_t txflt = 0;

    if (strcmp(info->devtype, "cpld") == 0)
    {
        status = board_i2c_cpld_read(info->devaddr , info->offset);
        if (status < 0)
            return status;
        else
        {
            txflt = ((status & BIT_INDEX(info->mask)) == info->cmpval) ? 1 : 0;
            sfp_dbg(KERN_INFO "\nModule TxFault :0x%x, reg_value = 0x%x\n", txflt, status);
        }

    } 
    data->txfault = txflt;

    return 0;
}

int sonic_i2c_set_mod_reset(struct i2c_client *client, XCVR_ATTR *info, struct xcvr_data *data)
{
    int status = 0;
    unsigned int val_mask = 0;
    uint8_t reg;

    if (strcmp(info->devtype, "cpld") == 0)
    {
        if(data->reset == 1) { 
            if(info->cmpval == 0)
                val_mask = ~(BIT_INDEX(info->mask));
            else
                val_mask = BIT_INDEX(info->mask);
        }
        else {
            if(info->cmpval == 0)
                val_mask = BIT_INDEX(info->mask);
            else
                val_mask = ~(BIT_INDEX(info->mask));
        }

        status = board_i2c_cpld_read(info->devaddr , info->offset);
        if (status < 0)
            return status;
        else
        {
            reg = status & val_mask;
            status = board_i2c_cpld_write(info->devaddr, info->offset, reg);
        }
    }

    return status;
}

int sonic_i2c_set_mod_lpmode(struct i2c_client *client, XCVR_ATTR *info, struct xcvr_data *data)
{
    int status = 0;
    unsigned int val_mask = 0;
    uint8_t reg;

    if (strcmp(info->devtype, "cpld") == 0)
    {
        if(data->lpmode == 1) { 
            if(info->cmpval == 0)
                val_mask = ~(BIT_INDEX(info->mask));
            else
                val_mask = BIT_INDEX(info->mask);
        }
        else {
            if(info->cmpval == 0)
                val_mask = BIT_INDEX(info->mask);
            else
                val_mask = ~(BIT_INDEX(info->mask));
        }

        status = board_i2c_cpld_read(info->devaddr , info->offset);
        if (status < 0)
            return status;
        else
        {
            reg = status & val_mask;
            status = board_i2c_cpld_write(info->devaddr, info->offset, reg);
        }
    }

    return status;
}

int sonic_i2c_set_mod_txdisable(struct i2c_client *client, XCVR_ATTR *info, struct xcvr_data *data)
{
    int status = 0;
    unsigned int val_mask = 0;
    uint8_t reg;

    if (strcmp(info->devtype, "cpld") == 0)
    {
        if(data->txdisable == 1) { 
            if(info->cmpval == 0)
                val_mask = ~(BIT_INDEX(info->mask));
            else
                val_mask = BIT_INDEX(info->mask);
        }
        else {
            if(info->cmpval == 0)
                val_mask = BIT_INDEX(info->mask);
            else
                val_mask = ~(BIT_INDEX(info->mask));
        }

        status = board_i2c_cpld_read(info->devaddr , info->offset);
        if (status < 0)
            return status;
        else
        {
            reg = status & val_mask;
            status = board_i2c_cpld_write(info->devaddr, info->offset, reg);
        }
    }

    return status;
}

ssize_t get_module_presence(struct device *dev, struct device_attribute *da,
             char *buf)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    struct i2c_client *client = to_i2c_client(dev);
    struct xcvr_data *data = i2c_get_clientdata(client);
    XCVR_PDATA *pdata = (XCVR_PDATA *)(client->dev.platform_data);
    XCVR_ATTR *attr_data = NULL;
    XCVR_SYSFS_ATTR_OPS *attr_ops = NULL;
    int status = 0, i;

    for (i=0; i<pdata->len; i++)
    {
        attr_data = &pdata->xcvr_attrs[i];
        /*printk(KERN_ERR "\n attr_data->devaddr: 0x%x, attr_data->mask:0x%x, attr_data->offset:0x%x\n", */
        /*attr_data->devaddr, attr_data->mask, attr_data->offset);*/
        if (strcmp(attr_data->aname, attr->dev_attr.attr.name) == 0)
        {
            attr_ops = &xcvr_ops[attr->index];

            mutex_lock(&data->update_lock);
            if (attr_ops->pre_get != NULL)
            {
                status = (attr_ops->pre_get)(client, attr_data, data);
                if (status!=0)
                    printk(KERN_ERR "%s: pre_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
            } 
            if (attr_ops->do_get != NULL)
            {
                status = (attr_ops->do_get)(client, attr_data, data);
                if (status!=0)
                    printk(KERN_ERR "%s: do_get function fails for %s attribute. ret %d\n", __FUNCTION__, attr_data->aname, status);

            }
            if (attr_ops->post_get != NULL)
            {
                status = (attr_ops->post_get)(client, attr_data, data);
                if (status!=0)
                    printk(KERN_ERR "%s: post_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
            }
            mutex_unlock(&data->update_lock);
            return sprintf(buf, "%d\n", data->modpres);
        }
    }
    return sprintf(buf, "%s","");
}

ssize_t get_module_reset(struct device *dev, struct device_attribute *da,
             char *buf)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    struct i2c_client *client = to_i2c_client(dev);
    struct xcvr_data *data = i2c_get_clientdata(client);
    XCVR_PDATA *pdata = (XCVR_PDATA *)(client->dev.platform_data);
    XCVR_ATTR *attr_data = NULL;
    XCVR_SYSFS_ATTR_OPS *attr_ops = NULL;
    int status = 0, i;

    for (i=0; i<pdata->len; i++)
    {
        attr_data = &pdata->xcvr_attrs[i];
        if (strcmp(attr_data->aname, attr->dev_attr.attr.name) == 0)
        {
            attr_ops = &xcvr_ops[attr->index];

            mutex_lock(&data->update_lock);
            if (attr_ops->pre_get != NULL)
            {
                status = (attr_ops->pre_get)(client, attr_data, data);
                if (status!=0)
                    printk(KERN_ERR "%s: pre_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
            } 
            if (attr_ops->do_get != NULL)
            {
                status = (attr_ops->do_get)(client, attr_data, data);
                if (status!=0)
                    printk(KERN_ERR "%s: do_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);

            }
            if (attr_ops->post_get != NULL)
            {
                status = (attr_ops->post_get)(client, attr_data, data);
                if (status!=0)
                    printk(KERN_ERR "%s: post_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
            }

            mutex_unlock(&data->update_lock);

            return sprintf(buf, "%d\n", data->reset);
        }
    }
    return sprintf(buf, "%s","");
}

ssize_t set_module_reset(struct device *dev, struct device_attribute *da, const char *buf, 
        size_t count)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    struct i2c_client *client = to_i2c_client(dev);
    struct xcvr_data *data = i2c_get_clientdata(client);
    XCVR_PDATA *pdata = (XCVR_PDATA *)(client->dev.platform_data);
    XCVR_ATTR *attr_data = NULL;
    XCVR_SYSFS_ATTR_OPS *attr_ops = NULL;
    int status = 0, i;
    unsigned int set_value;

    for (i=0; i<pdata->len; i++)
    {
        attr_data = &pdata->xcvr_attrs[i];
        if (strcmp(attr_data->aname, attr->dev_attr.attr.name) == 0)
        {
            attr_ops = &xcvr_ops[attr->index];
                if(kstrtoint(buf, 10, &set_value))
                    return -EINVAL;

            data->reset = set_value;

            mutex_lock(&data->update_lock);
            
            if (attr_ops->pre_set != NULL)
            {
                status = (attr_ops->pre_set)(client, attr_data, data);
                if (status!=0)
                    printk(KERN_ERR "%s: pre_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
                }
            if (attr_ops->do_set != NULL)
            {
                status = (attr_ops->do_set)(client, attr_data, data);
                if (status!=0)
                    printk(KERN_ERR "%s: do_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);

            }
            if (attr_ops->post_set != NULL)
            {
                status = (attr_ops->post_set)(client, attr_data, data);
                if (status!=0)
                    printk(KERN_ERR "%s: post_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
            } 
            mutex_unlock(&data->update_lock);

            return count;
        }
    }
    return -EINVAL;
}

ssize_t get_module_intr_status(struct device *dev, struct device_attribute *da,
             char *buf)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    struct i2c_client *client = to_i2c_client(dev);
    struct xcvr_data *data = i2c_get_clientdata(client);
    XCVR_PDATA *pdata = (XCVR_PDATA *)(client->dev.platform_data);
    XCVR_ATTR *attr_data = NULL;
    XCVR_SYSFS_ATTR_OPS *attr_ops = NULL;
    int status = 0, i;

    for (i=0; i<pdata->len; i++)
    {
        attr_data = &pdata->xcvr_attrs[i];
        if (strcmp(attr_data->aname, attr->dev_attr.attr.name) == 0)
        {
            attr_ops = &xcvr_ops[attr->index];

            mutex_lock(&data->update_lock);
            if (attr_ops->pre_get != NULL)
            {
                status = (attr_ops->pre_get)(client, attr_data, data);
                if (status!=0)
                    printk(KERN_ERR "%s: pre_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
            } 
            if (attr_ops->do_get != NULL)
            {
                status = (attr_ops->do_get)(client, attr_data, data);
                if (status!=0)
                    printk(KERN_ERR "%s: do_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);

            }
            if (attr_ops->post_get != NULL)
            {
                status = (attr_ops->post_get)(client, attr_data, data);
                if (status!=0)
                    printk(KERN_ERR "%s: post_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
            }

            mutex_unlock(&data->update_lock);
            return sprintf(buf, "%d\n", data->intr_status);
        }
    }
    return sprintf(buf, "%s","");
}

int get_xcvr_module_attr_data(struct i2c_client *client, struct device *dev, 
                            struct device_attribute *da, XCVR_ATTR *xattr)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    XCVR_PDATA *pdata = (XCVR_PDATA *)(client->dev.platform_data);
    XCVR_ATTR *attr_data = NULL;
    int i;

    for (i=0; i < pdata->len; i++)
    {
        attr_data = &pdata->xcvr_attrs[i];
        if (strcmp(attr_data->aname, attr->dev_attr.attr.name) == 0)
        {
            xattr = attr_data;
            return 1;
        }
    }
    return 0;
}

ssize_t get_module_lpmode(struct device *dev, struct device_attribute *da, char *buf)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    struct i2c_client *client = to_i2c_client(dev);
    struct xcvr_data *data = i2c_get_clientdata(client);
    XCVR_ATTR *attr_data = NULL;
    XCVR_SYSFS_ATTR_OPS *attr_ops = NULL;
    int status = 0;

    if(get_xcvr_module_attr_data(client, dev, da, attr_data) && (attr_data != NULL))
    {
        attr_ops = &xcvr_ops[attr->index];

        mutex_lock(&data->update_lock);
        if (attr_ops->pre_get != NULL)
        {
            status = (attr_ops->pre_get)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: pre_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
        } 
        if (attr_ops->do_get != NULL)
        {
            status = (attr_ops->do_get)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: do_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);

        }
        if (attr_ops->post_get != NULL)
        {
            status = (attr_ops->post_get)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: post_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
        }
        mutex_unlock(&data->update_lock);

        return sprintf(buf, "%d\n", data->lpmode);
    }
    else
        return sprintf(buf,"%s","");
}

ssize_t set_module_lpmode(struct device *dev, struct device_attribute *da, const char *buf, 
        size_t count)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    struct i2c_client *client = to_i2c_client(dev);
    struct xcvr_data *data = i2c_get_clientdata(client);
    int status = 0;
    uint32_t set_value;
    XCVR_ATTR *attr_data = NULL;
    XCVR_SYSFS_ATTR_OPS *attr_ops = NULL;

    if(get_xcvr_module_attr_data(client, dev, da, attr_data) && (attr_data != NULL))
    {
        attr_ops = &xcvr_ops[attr->index];
            if(kstrtoint(buf, 10, &set_value))
                return -EINVAL;

        data->lpmode = set_value;

        mutex_lock(&data->update_lock);
        
        if (attr_ops->pre_set != NULL)
        {
            status = (attr_ops->pre_set)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: pre_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
            }
        if (attr_ops->do_set != NULL)
        {
            status = (attr_ops->do_set)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: do_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);

        }
        if (attr_ops->post_set != NULL)
        {
            status = (attr_ops->post_set)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: post_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
        } 
        mutex_unlock(&data->update_lock);
    }
    return count;
}

ssize_t get_module_rxlos(struct device *dev, struct device_attribute *da,
             char *buf)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    struct i2c_client *client = to_i2c_client(dev);
    struct xcvr_data *data = i2c_get_clientdata(client);
    int status = 0;
    XCVR_ATTR *attr_data = NULL;
    XCVR_SYSFS_ATTR_OPS *attr_ops = NULL;

    if(get_xcvr_module_attr_data(client, dev, da, attr_data) && (attr_data != NULL))
    {
        attr_ops = &xcvr_ops[attr->index];

        mutex_lock(&data->update_lock);
        if (attr_ops->pre_get != NULL)
        {
            status = (attr_ops->pre_get)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: pre_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
        } 
        if (attr_ops->do_get != NULL)
        {
            status = (attr_ops->do_get)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: do_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);

        }
        if (attr_ops->post_get != NULL)
        {
            status = (attr_ops->post_get)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: post_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
        }
        mutex_unlock(&data->update_lock);
        return sprintf(buf, "%d\n", data->rxlos);
    }
    else
        return sprintf(buf,"%s","");
}

ssize_t get_module_txdisable(struct device *dev, struct device_attribute *da,
             char *buf)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    struct i2c_client *client = to_i2c_client(dev);
    struct xcvr_data *data = i2c_get_clientdata(client);
    int status = 0;
    XCVR_ATTR *attr_data = NULL;
    XCVR_SYSFS_ATTR_OPS *attr_ops = NULL;
    
    if(get_xcvr_module_attr_data(client, dev, da, attr_data) && (attr_data != NULL))
    {
        attr_ops = &xcvr_ops[attr->index];

        mutex_lock(&data->update_lock);
        if (attr_ops->pre_get != NULL)
        {
            status = (attr_ops->pre_get)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: pre_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
        }
        if (attr_ops->do_get != NULL)
        {
            status = (attr_ops->do_get)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: do_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);

        }
        if (attr_ops->post_get != NULL)
        {
            status = (attr_ops->post_get)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: post_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
        }
        mutex_unlock(&data->update_lock);
        return sprintf(buf, "%d\n", data->txdisable);
    }
    else
        return sprintf(buf,"%s","");
}

ssize_t set_module_txdisable(struct device *dev, struct device_attribute *da, const char *buf, 
        size_t count)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    struct i2c_client *client = to_i2c_client(dev);
    struct xcvr_data *data = i2c_get_clientdata(client);
    int status = 0;
    uint32_t set_value;
    XCVR_ATTR *attr_data = NULL;
    XCVR_SYSFS_ATTR_OPS *attr_ops = NULL;

    if(get_xcvr_module_attr_data(client, dev, da, attr_data) && (attr_data != NULL))
    {
        attr_ops = &xcvr_ops[attr->index];
            if(kstrtoint(buf, 10, &set_value))
                return -EINVAL;

        data->txdisable = set_value;

        mutex_lock(&data->update_lock);
        
        if (attr_ops->pre_set != NULL)
        {
            status = (attr_ops->pre_set)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: pre_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
            }
        if (attr_ops->do_set != NULL)
        {
            status = (attr_ops->do_set)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: do_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);

        }
        if (attr_ops->post_set != NULL)
        {
            status = (attr_ops->post_set)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: post_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
        } 
        mutex_unlock(&data->update_lock);
    }
    return count;
}

ssize_t get_module_txfault(struct device *dev, struct device_attribute *da,
             char *buf)
{
    struct sensor_device_attribute *attr = to_sensor_dev_attr(da);
    struct i2c_client *client = to_i2c_client(dev);
    struct xcvr_data *data = i2c_get_clientdata(client);
    int status = 0;
    XCVR_ATTR *attr_data = NULL;
    XCVR_SYSFS_ATTR_OPS *attr_ops = NULL;

    if(get_xcvr_module_attr_data(client, dev, da, attr_data) && (attr_data != NULL))
    {
        attr_ops = &xcvr_ops[attr->index];

        mutex_lock(&data->update_lock);
        if (attr_ops->pre_get != NULL)
        {
            status = (attr_ops->pre_get)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: pre_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
        } 
        if (attr_ops->do_get != NULL)
        {
            status = (attr_ops->do_get)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: do_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);

        }
        if (attr_ops->post_get != NULL)
        {
            status = (attr_ops->post_get)(client, attr_data, data);
            if (status!=0)
                printk(KERN_ERR "%s: post_get function fails for %s attribute\n", __FUNCTION__, attr_data->aname);
        }
        mutex_unlock(&data->update_lock);
        return sprintf(buf, "%d\n", data->txfault);
    }
    return sprintf(buf,"%s","");
}
