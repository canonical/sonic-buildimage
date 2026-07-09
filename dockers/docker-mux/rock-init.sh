#!/usr/bin/env bash

# Generate supervisord config file
mkdir -p /etc/supervisor/conf.d/

TZ=$(cat /etc/timezone)
rm -rf /etc/localtime
ln -sf /usr/share/zoneinfo/$TZ /etc/localtime
