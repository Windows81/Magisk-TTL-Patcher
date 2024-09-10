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

# mirror func without init_boot
find_kern_boot_image() {
  BOOTIMAGE=
  if [ ! -z $SLOT ]; then
    BOOTIMAGE=$(find_block "ramdisk$SLOT" "recovery_ramdisk$SLOT" "boot$SLOT")
  else
    BOOTIMAGE=$(find_block ramdisk recovery_ramdisk kern-a android_boot kernel bootimg boot lnx boot_a)
  fi
  if [ -z $BOOTIMAGE ]; then
    # Lets see what fstabs tells me
    BOOTIMAGE=$(grep -v '#' /etc/*fstab* | grep -E '/boot(img)?[^a-zA-Z]' | grep -oE '/dev/[a-zA-Z0-9_./-]*' | head -n 1)
  fi
}

# use util_functions to find the boot partition
find_kern_boot_image

if [ ! -z $BOOTIMAGE ] && [ -f $MODDIR/boot.img ]; then
    # Flash original boot image
    flash_image $MODDIR/boot.img "$BOOTIMAGE"
fi
