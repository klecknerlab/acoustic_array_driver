# import tinyprog
import time
import struct


class Controller(object):
    def __init__(self, dev_id='1209:6130', bootloader_ids = ('1d50:6130', '1209:2100')):
        ports = get_ports(dev_id)

        if not ports:
            reset_some = False

            for bid in bootloader_ids:
                ports_bl = get_ports(bid)

                if ports_bl:
                    print("Found a TinyFPGA in bootloader mode at %s... trying to reset." % dev_id)
                    for p in ports_bl:
                        p.__enter__()
                        p.write(b'\x00')
                        p.__exit__(None, None, None)
                        reset_some = True

                time.sleep(0.5)

            if reset_some:
                ports = get_ports(dev_id)
                if not ports:
                    raise RuntimeError('No devices found with address %s!' % dev_id)
                else:
                    print('That worked!')
            else:
                raise RuntimeError('No devices found with address %s, or TinyFPGAs in bootloader mode.' % dev_id)

        self.port = ports[0]
        self.port.__enter__()

    def cmd(self, cmd, val1=0, val2=0, val3=0):
        if type(cmd) is str: cmd = bytes(cmd, encoding='utf-8')
        self.port.write(struct.pack(">cBBB", cmd, val1, val2, val3))

        # Capital letter commands return 3 bytes (always)
        if not (ord(cmd) & 32):
            return struct.unpack(">BBBB", self.port.read(4))
        else:
            return None

    def write_channel(self, channel, duty, phase, check=True):
        retvals = self.cmd(b"W" if check else "w", 0, duty, phase)
        if check and retvals[0] != 0:
                raise ValueError('Write channel returned error code %d' % retvals[0])

    def select_bank(self, read=255, write=255, check=True):
        retvals = self.cmd(b"B" if check else "b", 0, read, write)
        if check and retvals[0] != 0:
                raise ValueError('Write channel returned error code %d' % retvals[0])

# -----------------------------------------------------------------------------
# The following functions are copied from TinyProg
# (https://github.com/tinyfpga/TinyFPGA-Bootloader/tree/master/programmer)
# TinyProg does not appear to have a license, so I guess it's ok?!
# -----------------------------------------------------------------------------
from pkg_resources import get_distribution, DistributionNotFound
from serial.tools.list_ports import comports
import serial
import platform

try:
    __version__ = get_distribution(__name__).version
except DistributionNotFound:
    # package is not installed
    __version__ = "unknown"

try:
    from .full_version import __full_version__
    if not __full_version__:
        raise ValueError
except (ImportError, ValueError):
    __full_version__ = "unknown"


use_libusb = False
use_pyserial = False

def get_ports(device_id):
    """
    Return ports for all devices with the given device_id.

    :param device_id: USB VID and PID.
    :return: List of port objects.
    """

    ports = []

    if platform.system() == "Darwin" or use_libusb:
        import usb
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

    # MacOS is not playing nicely with the serial drivers for the bootloader
    if platform.system() != "Darwin" or use_pyserial:
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

    def __str__(self):
        return self.port_name

    def __enter__(self):
        # Timeouts:
        # - Read:  2.0 seconds (timeout)
        # - Write: 5.0 seconds (writeTimeout)
        #
        # Rationale: hitting the writeTimeout is fatal, so it pays to be
        # patient in case there is a brief delay; readTimeout is less
        # fatal, but can result in short reads if it is hit, so we want
        # a timeout high enough that is never hit normally.  In practice
        # 1.0 seconds is *usually* enough, so the chosen values are double
        # and five times the "usually enough" values.
        #
        try:
            self.ser = serial.Serial(
                self.port_name, timeout=2.0, writeTimeout=5.0).__enter__()
        except serial.SerialException as e:
            raise PortError("Failed to open serial port:\n%s" % str(e))
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        try:
            self.ser.__exit__(exc_type, exc_val, exc_tb)
        except serial.SerialException as e:
            raise PortError("Failed to close serial port:\n%s" % str(e))

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
