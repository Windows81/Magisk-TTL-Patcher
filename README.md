# [[Magisk] Tethering TTL/HL Patcher](https://xdaforums.com/t/magisk-tethering-ttl-hl-patcher.4623067/)

_Authored and maintained on XDA by Fddm._

This is an **experimental** generic patcher specifically for Android devices with AArch64 little-endian kernels(i.e. most Android phones). It's purpose is to replace the TTL/HL decrement for forwarded IP traffic with a set value of 64. Why you might want to do this is anyone's guess 🙄 Just use responsibly.

It requires Magisk to install and has support for KernelSU and APatch since version _alpha10_. I tried to make this as generic as possible, but there are a ton of different devices out there. Please report any issues and I will try to resolve them if I can.

Apart from the kernel/bpf patches above, the module adds 'net.tethering.noprovisioning=true' in your build properties to allow tethering where it might otherwise be disabled. It tries to insert 'dun' into the 'APN Type' field of your active APN settings with 'content' commands if not already set to ensure that hidden dun APNs are not used. It also disables 'Tethering hardware acceleration' using the command 'settings put global tether_offload_disabled 1' so forwarded traffic will be handled in the kernel rather than offloaded onto the SoC. The importance of these settings depends entirely on the specific device and carrier.

After uninstalling you will need to reboot once to reflash your original boot image and again to boot from it. Your 'APN Type' and 'Tethering hardware acceleration' settings will also need to be reverted manually if desirable.

**Important: this module should be uninstalled and the device rebooted before taking a system update.** The kernel patch will be removed by the update and uninstalling the Magisk module afterwards will restore the kernel to the version before the update. If you find yourself in this state, simply delete the `hoppatch` folder under `/data/adb/modules`. The bpf patches that survive the update might be enough to mask your TTL/HL on Android 11+, but it is not recommended as not all traffic goes through it.

Note: Since alpha10, you can force an install without mobile service/SIM card by creating a file named `skip_apn` in your internal storage.

## Patches Applied

`/kernel/<vendor>/<kernel>/net/ipv4/ipforward.c`
in `ip_forward()` (`ip_decrease_ttl` is inlined from `/kernel/<vendor>/<kernel>/include/net/ip.h`):

```c
u32 check;
```

...

```c
    //ip_decrease_ttl(iph);
    check = (__force u32)iph->check;
    check += (__force u32)(iph->ttl);
    iph->ttl = 0x40;
    check -= (__force u32)(iph->ttl);
    iph->check = (__force __sum16)(check + (check>>0x10));
```

`/system/netd/bpf_progs/offload.c` (Android 11)
`/packages/modules/Connectivity/bpf_progs/offload.c` (Android 12+)
in `do_forward6()`:

```c
    //--ip6->hop_limit;
    ip6->hop_limit = 64;
```

in `do_forward4_bottom()` (Android 12+ only)

```c
    //const __be16 new_ttl_proto = old_ttl_proto - htons(0x0100);
    const __be16 new_ttl_proto = htons(0x4000) + (old_ttl_proto & htons(0x00ff));
```

## Changelog

- alpha10 - add KernelSU and APatch support, add bypass for the APN check
- alpha9 - fix for newer devices with init_boot partition, patch system offload.o for A11
- alpha8 - fix signature for ip_decrease_ttl
- alpha7 - inverted tether_offload_disabled check so it isn't skipped if set with a boolean value
- alpha6 - simplified ip_decrease_ttl kernel patch (removed ip_send_check call, removed vmlinux-to-elf and jump calculation code)
- alpha5 - ported kallsyms_finder code from vmlinux-to-elf for detecting kallsyms_offsets/kallsyms_addresses, fixed and reintroduced the uninstaller script
- alpha4 - simplified the BPF signature and patch for ip6_forward, log more info and add short waits for debugging purposes
- alpha3 - fixed patcher support for Android versions earlier than 11, fixed a bug that prevented install on previous version, removed uninstall script
- alpha2 - added rules to make the kernel patch signatures stricter, added code comments to the ip4_forward BPF patches, added an extra check to the installation script to fail if no BPF modules are found (Android 11+)
- alpha1 - initial release

## TODO

- Add support for 32-bit kernels
- Finish the updated kernel patcher so more advanced rules can be used
