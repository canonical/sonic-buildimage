#!/usr/bin/env python3
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

import common 
import poe

global PSU_max_power
PSU_max_power = 740

class DeviceThread(common.threading.Thread):
	def __init__(self,threadname, q):
		common.threading.Thread.__init__(self,name = threadname)
		self.queue = q

	def run(self):
		while common.RUN:
			message = self.queue.get()
			self.onMessage(message)

	def onMessage(self, message):
		"""
		Commands:
			led		: Led controls
			locate		: Blink locator LED
			sensors		: Read HW monitors
		"""

		if len(message.command) < 1:
			result = self.onMessage.__doc__
		else:
			if message.command[0] == 'init':
				result = deviceInit()
			else:
				result = self.onMessage.__doc__

		if (message.callback is not None):
			 message.callback(result)


class PlatformStatusThread(common.threading.Thread):
	def __init__(self,threadname, timer):
		self.running = True
		common.threading.Thread.__init__(self,name = threadname)
		self.timer = timer
		self.fan_led_status = 'off'
		self.psu_led_status = 'off'

	def run(self):
		while common.RUN:
			self.checkPlatformStatus()
			common.time.sleep(self.timer)

	def checkPlatformStatus(self):
		total_result = common.PASS
		total_result += self.checkTempStatus()
		total_result += self.checkFanStatus()
		total_result += self.checkPsuStatus()
		total_result += self.checkPoeStatus()

	def checkTempStatus(self):
		return common.PASS

	def checkFanStatus(self):
		return common.PASS

	def checkPsuStatus(self):
		return common.PASS

	def checkPoeStatus(self):
		global PSU_max_power
		poe.poe_update_percent(PSU_max_power)
		return common.PASS

def deviceInit():

	#Set tx disable
	for x in range(0, common.SFP_MAX_NUM):
		path = common.I2C_PREFIX + common.SFP_PATH  + 'SFP_tx_ctrl_' + str(x+49)
		result = common.writeFile(path, "0")

	#Set led to green
	result = common.writeFile(common.I2C_PREFIX + common.LED_PATH  + 'led_sys', "1")

	try:
		status, output = common.doBash("decode-syseeprom -p")
		hwsku = output
	except:
		hwsku = ''
	device_type = 0
	global PSU_max_power

	if hwsku in ["CX204Y-24GT-HPW1-M-AC", "CX204Y-24GT-M-SWP2"]:
		PSU_max_power = 370
		device_type = 1
	elif hwsku in ["CX204Y-24GT-HPW2-M-AC", "CX204Y-24GT-M-SWP4"]:
		PSU_max_power = 740
		device_type = 2
	elif hwsku in ["CX204Y-48GT-HPW2-M-AC", "CX204Y-48GT-M-SWP4"]:
		PSU_max_power = 740
		device_type = 2

	#Set device_type
	result = common.writeFile(common.I2C_PREFIX + common.SYS_PATH + 'device_type', device_type)
	return
