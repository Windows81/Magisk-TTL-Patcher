MODDIR=${0%/*}

# check environment
[ $API -lt 23 ] && abort "! Magisk only support Android 6.0 and above"
[ ! $IS64BIT ] && abort "! Only has patches for AArch64, request support"
[ ! $BOOTMODE ] && abort "! Install through Magisk's app"

# Print device and firmware information for debugging
ui_print "- Codename: $(getprop ro.build.product)"
ui_print "- Device: $(getprop ro.build.display.id)"
ui_print "- Fingerprint: $(getprop ro.build.fingerprint)"

# import Magisk util_functions
. /data/adb/magisk/util_functions.sh

# detect boot slot
SLOT=$(grep_cmdline androidboot.slot_suffix)
if [ -z $SLOT ]; then
    SLOT=$(grep_cmdline androidboot.slot)
    [ -z $SLOT ] || SLOT=_${SLOT}
fi
[ "$SLOT" = "normal" ] && unset SLOT
[ -z $SLOT ] || ui_print "- Current boot slot: $SLOT"

# set Magisk varibles
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

# find boot partition
find_kern_boot_image
[ -z $BOOTIMAGE ] && abort "! Unable to detect boot partition"
ui_print "- Target image: $BOOTIMAGE"

# change to working directory
cd $MODPATH

# dump boot image
if [ -c "$BOOTIMAGE" ]; then
    nanddump -f boot.img "$BOOTIMAGE"
else
    dd if="$BOOTIMAGE" of=boot.img
fi

# unpack boot image
ui_print "- Unpacking boot image with magiskboot"
chmod +x /data/adb/magisk/magiskboot
/data/adb/magisk/magiskboot unpack boot.img
[ $? -ne 0 ] && abort "! Failed to unpack boot image"
sleep 1

# patch with patcher
ui_print "- Patching boot image..."
mkdir dalvik-cache
ANDROID_DATA=$PWD dalvikvm -cp kernel_patcher.zip kernel_patcher
[ $? -ne 0 ] && abort "! Kernel patcher failed"
sleep 1

# repack patched boot image
ui_print "- Repacking boot image..."
rm kernel && mv kernel.patched kernel
/data/adb/magisk/magiskboot repack boot.img
[ $? -ne 0 ] && abort "! Failed to repack boot image"
sleep 1

# offload.o was added since Android 11
if [ $API -ge 30 ]; then
    # patching offload.o and appending bind commands to post-fs-data.sh
    ui_print "- Patching offload.o..."
    cp post-fs-data.sh.template post-fs-data.sh
    offloadpath=/system/etc/bpf/
    mkdir -p $MODPATH$offloadpath
    find $offloadpath -maxdepth 1 -type f -iname "offload*.o" | while read offloadfile; do
        ui_print "- Found BPF module: $offloadfile"
        cp $offloadfile $MODPATH$offloadpath
        ANDROID_DATA=$PWD dalvikvm -cp bpf_patcher.zip bpf_patcher $MODPATH$offloadfile $API
        [ $? -ne 0 ] && abort "! BPF patcher failed"
        echo "mount -o ro,bind \$MODDIR$offloadfile.patched $offloadfile" >> post-fs-data.sh
        touch flag
        sleep 1
    done
    find /apex/com.android.tethering*/etc/bpf/ -maxdepth 0 -type d | while read offloadpath; do
        mkdir -p $MODPATH$offloadpath
        find $offloadpath -maxdepth 1 -type f -iname "offload*.o" | while read offloadfile; do
            ui_print "- Found BPF module: $offloadfile"
            cp $offloadfile $MODPATH$offloadpath
            ANDROID_DATA=$PWD dalvikvm -cp bpf_patcher.zip bpf_patcher $MODPATH$offloadfile $API
            [ $? -ne 0 ] && abort "! BPF patcher failed"
            echo "mount -o ro,bind \$MODDIR$offloadfile.patched $offloadfile" >> post-fs-data.sh
            touch flag
            sleep 1
        done
    done
    [ ! -f flag ] && abort "! Unable to locate BPF module"
fi

# disabling 'Tethering hardware acceleration'
if [ ! $(settings get global tether_offload_disabled) == "1" ]; then
    ui_print "- Disabling 'Tethering hardware acceleration'..."
    settings put global tether_offload_disabled 1
else
    ui_print "- 'Tethering hardware acceleration' already disabled"
fi

# adding dun to APN Type
apninfo=$(content query --uri content://telephony/carriers/preferapn --projection _id:type)
echo $apninfo | grep "_id" >/dev/null
[ $? -ne 0 ] && abort "! Failed to dump APN information"
apnid=$(echo $apninfo | cut -F2 -d"_id=" | cut -F1 -d",")
apntype=$(echo $apninfo | cut -F2 -d"type=")
echo $apntype | grep "dun" >/dev/null
if [ $? -ne 0 ]; then
    ui_print "- Inserting 'dun' into APN Type"
    if [ "${str: -1}" -eq "," ]; then
        content update --uri content://telephony/carriers --where "_id=$apnid" --bind type:s:"$apntype"dun
    else
        content update --uri content://telephony/carriers --where "_id=$apnid" --bind type:s:"$apntype",dun
    fi
    # revert edited=4 that prevents APN from being edited from GUI
    apninfo=$(content query --uri content://telephony/carriers/preferapn --projection edited)
    echo $apninfo | grep "edited" >/dev/null
    if [ $? -eq 0 ]; then
        content update --uri content://telephony/carriers --where "_id=$apnid" --bind edited:s:1
    fi
else
    ui_print "- APN Type already contains a 'dun' entry"
fi

# flash new-boot.img
ui_print "- Flashing modified boot image..."
flash_image new-boot.img "$BOOTIMAGE"
[ $? -ne 0 ] && abort "! Failed to flash modified boot image"
