import tinyprog
import time
import random

dev_id = '1209:6130'

ports = tinyprog.get_ports(dev_id)

bootloader_ids = ['1d50:6130', '1209:2100']


# print(ports_bl)

reset_some = False

if not ports:
    for id in bootloader_ids:
        ports_bl = tinyprog.get_ports(id)

        if ports_bl:
            print("Found a TinyFPGA in bootloader mode at %s... trying to reset." % id)
            for p in ports_bl:
                p.write('\x00')
                reset_some = True

        time.sleep(0.5)

    if reset_some:
        ports = tinyprog.get_ports(dev_id)
        if not ports:
            raise RuntimeError('No devices found with address %s!' % dev_id)
        else:
            print('That worked!')
    else:
        raise RuntimeError('No devices found with address %s, or TinyFPGAs in bootloader mode.' % id)

p = ports[0]

for n in range(200):
    cmd = bytes([random.randint(97, 122) for n in range (3)])
    p.write(cmd)
    print(cmd, p.read(3))

# print(p.read(3))
