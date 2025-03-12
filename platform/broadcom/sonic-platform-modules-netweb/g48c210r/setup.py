#!/usr/bin/env python

import os
from setuptools import setup
os.listdir

setup(
    name='g48c210r',
    version='1.0',
    description='Module to initialize Netweb G48C210R platforms',

    packages=['g48c210r'],
    package_dir={'g48c210r': 'g48c210r/classes'},
)
