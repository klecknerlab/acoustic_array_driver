# import tinyprog
import time
import struct


class Controller(object):
    def __init__(self, dev_id='1209:6130', bootloader_ids = ['1d50:6130', '1209:2100'], search_timeout=10):
        ports = get_ports(dev_id)

        if not ports:
            reset_some = False

            for id in bootloader_ids:
                ports_bl = get_ports(id)

                if ports_bl:
                    print("Found a TinyFPGA in bootloader mode at %s... trying to reset." % id)
                    for p in ports_bl:
                        p.write(b'\x00')
                        p.close()

                        reset_some = True

            if reset_some:
                print("Searching for restarted device...")
                for n in range(2*search_timeout):
                    time.sleep(0.5)
                    try:
                        ports = get_ports(dev_id)
                    except:
                        ports = False
                    if ports: break

                if not ports:
                    raise RuntimeError('No devices found with address %s!' % dev_id)
                else:
                    print('Found it!')
            else:
                raise RuntimeError('No devices found with address %s, or TinyFPGAs in bootloader mode.' % id)

        self.port = ports[0]

    def __enter__(self):
        self.port.__enter__()
        return self

    def __exit__(self):
        self.port.__exit__()

    def cmd(self, cmd, val1=0, val2=0):
        if type(cmd) is str: cmd = bytes(cmd, encoding='utf-8')
        self.port.write(struct.pack(">cBB", cmd, val1, val2))

        # Capital letter commands return 3 bytes (always)
        if not (ord(cmd) & 32):
            return struct.unpack(">BBB", self.port.read(3))
        else:
            return None


# -----------------------------------------------------------------------------
# The following functions are copied from TinyProg
# (https://github.com/tinyfpga/TinyFPGA-Bootloader/tree/master/programmer)
# They were modified to streamline things -- we just need to get a port to talk
# TinyProg does not appear to have a license, so I guess it's ok?!
# -----------------------------------------------------------------------------

# from pkg_resources import get_distribution, DistributionNotFound
# from serial.tools.list_ports import comports
# import serial
import platform

# try:
#     __version__ = get_distribution(__name__).version
# except DistributionNotFound:
#     # package is not installed
#     __version__ = "unknown"
#
# try:
#     from .full_version import __full_version__
#     if not __full_version__:
#         raise ValueError
# except (ImportError, ValueError):
#     __full_version__ = "unknown"


_use_libusb = False

if platform.system() == "Darwin" or _use_libusb:
    import usb
    _use_libusb = True

else:
    import serial
    from serial.tools.list_ports import comports


def get_ports(device_id):
    """
    Return ports for all devices with the given device_id.

    :param device_id: USB VID and PID.
    :return: List of port objects.
    """

    ports = []

    if _use_libusb:
        vid, pid = [int(x, 16) for x in device_id.split(":")]

        try:
            ports += [
                UsbPort(usb, d)
                for d in usb.core.find(
                    idVendor=vid, idProduct=pid, find_all=True)
                if not d.is_kernel_driver_active(1)
            ]
        except usb.core.USBError as e:
            raise PortError("Failed to open USB:\n%s" % str(e))

    else:
        # get serial ports first
        ports += [
            SerialPort(p[0]) for p in comports() if device_id in p[2].lower()
        ]

    return ports


class PortError(Exception):
    pass


class SerialPort(object):
    def __init__(self, port_name):
        self.port_name = port_name
        self.ser = None

        try:
            self.ser = serial.Serial(
                self.port_name, timeout=2.0, writeTimeout=5.0).__enter__()
        except serial.SerialException as e:
            raise PortError("Failed to open serial port:\n%s" % str(e))

    def __str__(self):
        return self.port_name

    # def __enter__(self):
    #     # Timeouts:
    #     # - Read:  2.0 seconds (timeout)
    #     # - Write: 5.0 seconds (writeTimeout)
    #     #
    #     # Rationale: hitting the writeTimeout is fatal, so it pays to be
    #     # patient in case there is a brief delay; readTimeout is less
    #     # fatal, but can result in short reads if it is hit, so we want
    #     # a timeout high enough that is never hit normally.  In practice
    #     # 1.0 seconds is *usually* enough, so the chosen values are double
    #     # and five times the "usually enough" values.
    #     #
    #     try:
    #         self.ser = serial.Serial(
    #             self.port_name, timeout=2.0, writeTimeout=5.0).__enter__()
    #     except serial.SerialException as e:
    #         raise PortError("Failed to open serial port:\n%s" % str(e))
        #
        # return self
    #
    # def __exit__(self, exc_type, exc_val, exc_tb):
    #     try:
    #         self.ser.__exit__(exc_type, exc_val, exc_tb)
    #     except serial.SerialException as e:
    #         raise PortError("Failed to close serial port:\n%s" % str(e))

    def close(self, exc_type=None, exc_val=None, exc_tb=None):
        try:
            self.ser.__exit__(exc_type, exc_val, exc_tb)
        except serial.SerialException as e:
            raise PortError("Failed to close serial port:\n%s" % str(e))

    def __enter__(self):
        return self

    def __exit__(self, exc_type=None, exc_val=None, exc_tb=None):
        self.close(exc_type=None, exc_val=None, exc_tb=None)

    def write(self, data):
        try:
            self.ser.write(data)
        except serial.SerialException as e:
            raise PortError("Failed to write to serial port:\n%s" % str(e))

    def flush(self):
        try:
            self.ser.flush()
        except serial.SerialException as e:
            raise PortError("Failed to flush serial port:\n%s" % str(e))

    def read(self, length):
        try:
            return self.ser.read(length)
        except serial.SerialException as e:
            raise PortError("Failed to read from serial port:\n%s" % str(e))


class UsbPort(object):
    def __init__(self, usb, device):
        self.usb = usb
        self.device = device
        usb_interface = device.configurations()[0].interfaces()[1]
        self.OUT = usb_interface.endpoints()[0]
        self.IN = usb_interface.endpoints()[1]

    def __str__(self):
        if self.device.port_number is not None:
            port_number = int(self.device.port_number)
        else:
            port_number = "[no port number]"
        return "USB %d.%s" % (self.device.bus, port_number)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        pass

    def write(self, data):
        try:
            self.OUT.write(data)
        except self.usb.core.USBError as e:
            raise PortError("Failed to write to USB:\n%s" % str(e))

    def flush(self):
        # i don't think there's a comparable function on pyusb endpoints
        pass

    def read(self, length):
        try:
            if length > 0:
                data = self.IN.read(length)
                return bytearray(data)
            else:
                return ""
        except self.usb.core.USBError as e:
            raise PortError("Failed to read from USB:\n%s" % str(e))

# -----------------------------------------------------------------------------
# END OF TINYPROG CODE
# -----------------------------------------------------------------------------
