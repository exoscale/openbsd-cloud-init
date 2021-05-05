OpenBSD initialization for cloud environments
=============================================

`openbsd-cloud-init` provides a dependency-free solution
for initializing [OpenBSD](http://www.openbsd.org) instances within cloud environments.

The aim is to provide loose compatibility with
[cloud-init](https://cloudinit.readthedocs.org/en/latest/) which has
positioned itself as the standard solution to perform first-boot
changes.

## Scope of openbsd-cloud-init

To keep within the spirit of security promoted by [OpenBSD](http://www.openbsd.org),
this tool will limit itself to a single first-boot run and will be as unintrusive
as possible by default. The following actions are currently supported:

- SSH [authorized_keys](http://www.openbsd.org/cgi-bin/man.cgi/OpenBSD-current/man8/sshd.8?query=sshd&sec=8) personalization if requested.
- Persistent hostname personalization if requested.
- Local host resolution personalization unless requested otherwise.
- Optional custom script execution.
- Packages installation (pkg_add) support.
- Custom commands (runcmd) execution.

## Future improvements

- [ ] Root disk resize
- [ ] Cloud-init user and group creation support
- [ ] Cloud-init write-file support
- [ ] Cloud-init custom package install support
- [ ] Cloud-init puppet initialization support
- [ ] Cloud-init resolv.conf personalization support

## Caveats

As it stands, `openbsd-cloud-init` will only work in KVM + virtio environments when metadata is
served from the same IP.

## Installing OpenBSD with openbsd-cloud-init support

As far as installing `openbsd-cloud-init` is concerned, a standard installation should
be carried out. Before the final reboot, carry out the following actions:

```bash
# mount /dev/sd0a /mnt
# mount /dev/sd0X /mnt/usr
# /mnt/usr/sbin/chroot /mnt
# mount -a
# ftp -o /usr/local/libdata/cloud-init.pl http://<server>/<path>/cloud-init.pl
# perl /usr/local/libdata/cloud-init.pl deploy
```

The last deploy step will carry out the following actions:

- Remove the configured root password, effectively disabling password logins
- Remove generated keys (for ike, isakmpd and SSH) and random seeds.
- Configure openbsd-cloud-init to run in `/etc/rc.local`
- Add a first boot indication by touch `/etc/cloud.init`

## Example environment

To create a compatible environment, the following steps can be taken,
assuming a Linux + KVM host environment:

Setting up a bridge for tap networking:

```bash
# brctl addbr br0
# ip link set br0 up
# ip addr add 10.0.38.1/24 dev br0
```

Configure dnsmasq to serve on the bridge:

```
interface=br0
bind-interfaces
dhcp-range=10.0.38.50,10.0.38.100,12h
domain=spootnik.org
```

Serve mock metadata:

Using `python -m http.server 80` (as root) you can serve the following
directory structure:

```
./cloud-init.pl => this script
./latest/meta-data/public-keys => "ssh-rsa ..." (your pubkey)
./latest/user-data => "#cloud-config\nfqdn: some.host.name\nmanage_etc_hosts: true\n"
```

Create a suitable disk (for instance `qemu-img -f qcow2 basedisk.qcow2 10G`), then
start an instance with an OpenBSD iso:



```
qemu-system-x86_64 \
    -M pc-1.0 -enable-kvm -nodefconfig -nodefaults \
    -rtc base=utc -cpu host -smp cpus=4 -m 2048 -vga cirrus \
    -netdev tap,id=hostnet0,vhost=on,ifname=tap0,script=qemu-ifup \
    -device virtio-net-pci,netdev=hostnet0,id=net0,mac=06:f8:ee:00:00:cf,bus=pci.0,addr=0x3 \
    -drive file=basedisk.qcow2,format=qcow2,cache=none,if=none,id=drive-virtio-disk0 \
    -device virtio-blk-pci,bus=pci.0,addr=0x4,drive=drive-virtio-disk0,id=virtio-disk0,bootindex=2 \
    -device isa-serial,chardev=charserial0,id=serial0 \
    -chardev pty,id=charserial0 \
    -name openbsd-guest -uuid 9e182286-92ec-4655-8b91-a1969fc0cbbb \
    -cdrom install56.iso -boot d
```

Install as explained above, then copy the resulting image, you have a template!
It can now be started with:

```
qemu-system-x86_64 \
    -M pc-1.0 -enable-kvm -nodefconfig -nodefaults \
    -rtc base=utc -cpu host -smp cpus=4 -m 2048 -vga cirrus \
    -netdev tap,id=hostnet0,vhost=on,ifname=tap0,script=qemu-ifup \
    -device virtio-net-pci,netdev=hostnet0,id=net0,mac=06:f8:ee:00:00:cf,bus=pci.0,addr=0x3 \
    -drive file=basedisk.qcow2,format=qcow2,cache=none,if=none,id=drive-virtio-disk0 \
    -device virtio-blk-pci,bus=pci.0,addr=0x4,drive=drive-virtio-disk0,id=virtio-disk0,bootindex=2 \
    -device isa-serial,chardev=charserial0,id=serial0 \
    -chardev pty,id=charserial0 \
    -name openbsd-guest -uuid 9e182286-92ec-4655-8b91-a1969fc0cbbb
```

And will fetch personalization from your mock metadata server, giving you
SSH public key access to a machine with a correct hostname and hosts file.

## License

```
Copyright (c) 2015 Pierre-Yves Ritschard

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
