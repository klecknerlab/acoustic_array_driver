import acoustic_array
import sys

# Open the phase controller
# with acoustic_array.Controller() as pc:
pc = acoustic_array.Controller()

# print(pc.port.ser)


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

try:
    n0 = int(sys.argv[1])
except:
    n0 = 0

for n in range(32):
    # Both phase and duty cycle range from 0-255, thus 128 is 50% duty

    # Each channel advances by 8 in phase -- smaller changes won't be
    #  visible, as the default driver has only 32 updates per cycle.
    phase = (n * 8) % 256
    # 50% duty cycle
    # duty = 128
    # duty = 128 if n == 0 else 8
    if n == n0:
        duty = 128
    elif n == (n0+1):
        duty = 64
    else:
        duty = 8

    # This command writes to the current address, and updates the address by one.
    # The returned data is the bank/channel just written.
    print('Sucessfully wrote data to:', pc.cmd('W', phase, duty))

# Select the output bank
print('Selected bank:', pc.cmd('B', 0, bank))
