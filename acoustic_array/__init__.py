import tinyprog
import time
import struct


class Controller(object):
    def __init__(self, dev_id='1209:6130', bootloader_ids = ['1d50:6130', '1209:2100']):
        ports = tinyprog.get_ports(dev_id)

        if not ports:
            reset_some = False

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

        self.port = ports[0]

    def cmd(self, cmd, val1=0, val2=0):
        if type(cmd) is str: cmd = bytes(cmd, encoding='utf-8')
        self.port.write(struct.pack(">cBB", cmd, val1, val2))

        # Capital letter commands return 3 bytes (always)
        if not (ord(cmd) & 32):
            return struct.unpack(">BBB", self.port.read(3))
        else:
            return None
