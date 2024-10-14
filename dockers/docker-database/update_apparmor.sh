#!/bin/bash
cp snap.database.database /var/lib/snapd/apparmor/profiles/ 
apparmor_parser -r /var/lib/snapd/apparmor/profiles/snap.database.database
