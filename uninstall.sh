MODDIR=${0%/*}

# import Magisk util_functions
. /data/adb/magisk/util_functions.sh

# detect boot slot
SLOT=$(grep_cmdline androidboot.slot_suffix)
if [ -z $SLOT ]; then
    SLOT=$(grep_cmdline androidboot.slot)
    [ -z $SLOT ] || SLOT=_${SLOT}
fi
[ "$SLOT" = "normal" ] && unset SLOT

# not uninstalling through recovery mode
RECOVERYMODE=false

# use util_functions to find the boot partition
find_boot_image

if [ ! -z $BOOTIMAGE ] && [ -f $MODDIR/boot.img ]; then
    # Flash original boot image
    flash_image $MODDIR/boot.img "$BOOTIMAGE"
fi
