#!/bin/bash
# Quelle(n):  c't 25/2016, S. 77
#             c't 26/2016, S. 12
#             https://wiki.ubuntuusers.de/Soundkarten_konfigurieren/HDA/#Lautsprecher-knacksen
# Enable Audio codec power management
echo 1 > /sys/module/snd_hda_intel/parameters/power_save
echo Y > /sys/module/snd_hda_intel/parameters/power_save_controller
