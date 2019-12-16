import tinyprog
import time
import struct


class PhaseController(object):
    def __init__(self, dev_id='1209:6130', bootloader_ids = ['1d50:6130', '1209:2100']):
        ports = tinyprog.get_ports(dev_id)

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

        self.port = ports[0]

    def cmd(self, cmd, val1=0, val2=0):
        if type(cmd) is str: cmd = bytes(cmd, encoding='utf-8')
        self.port.write(struct.pack(">cBB", cmd, val1, val2))

        # Capital letter commands return 3 bytes (always)
        if not (ord(cmd) & 32):
            return struct.unpack(">BBB", self.port.read(3))
        else:
            return None


if __name__ == '__main__':
    # Open the phase controller
    pc = PhaseController()

    # The controller has 32 output banks (0-31), and 256 channels (0-255).
    # Each pin on the output of the device controls 16 channels, i.e.
    #   FPGA pin 1: channels 0-15
    #   FPGA pin 2: channels 16-31
    #   ... and so on.
    # Additionally, pins 17-20 are the control outputs to the shift registers:
    #   FPGA pin 17: data (DS or pin 14 on 74LVC595)
    #   FPGA pin 18: shift clock (SHCP or pin 11 on 74LVC595)
    #   FPGA pin 19: output register clock (STCP or pin 12 on 74LVC595)
    # Each shift register only has 8 channels, however, you can get the full 16
    #   on each output pin by connecting Q7S (pin 9) of one 74LVC595 to DS (pin
    #   14) of the second.  SHCP and STCP should be connected to the same
    #   channels on the first register.
    # Note the additional requirements for each register:
    #   GND (PIN 8)  => ground (G on FPGA)
    #   ~MR (PIN 10) => 3.3 V (on FPGA)
    #   ~OE (PIN 13) => ground
    #   VCC (PIN 16) => 3.3 V
    #
    # At any given instance in time it is reading from one of the 32 `banks' to
    #   produce the output.  You can also write to any of these banks at any
    #   time; for example you might be reading from bank 1, then write to bank
    #   2 and switch over once you're finished writing.
    #
    # All writes to the device take a command character and two 1 byte data
    #   characters.  If the command character is capitalized, it will return
    #   a response, otherwise it will not.
    # The first response byte is an error code, which should always be 0.
    # The second two bytes vary based on the command.

    # Here we will write to and then switch to bank 12, which is arbitrary.
    bank = 12

    # Select address to write to = bank, channel
    # In this case we will write all 256 channels, so channel = 0
    print('Write address:', pc.cmd('A', bank, 0))

    for n in range(256):
        # Both phase and duty cycle range from 0-63, thus 32 is 50% duty

        # 50% duty cycle, varying over full range of phases for channels 0-15
        phase = (n % 16) * 4
        duty = 32

        # Use channel 2 as a check
        # if (n%16) == 2:
        #     phase = 0
        #     duty = 1

        # Here the phase varies over the channels, but the duty cycle also varies
        # so that the outputs go low at the same point.
        # phase = (n % 16) * 4
        # duty = phase

        # This command writes to the current address, and updates the address by one.
        # The returned data is the bank/channel just written.
        print('Sucessfully wrote data to:', pc.cmd('W', phase, duty))

    # Select the output bank
    print('Selected bank:', pc.cmd('B', 0, bank))
