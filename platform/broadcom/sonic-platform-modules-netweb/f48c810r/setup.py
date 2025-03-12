#!/usr/bin/env pytho

import os
import sys
from setuptools import setup
os.listdir

setup(
   name='f48c810r',
   version='1.0',
   description='Module to initialize NETWEB F48C810R platforms',
   
   packages=['f48c810r'],
   package_dir={'f48c810r': 'f48c810r/classes'},
)

