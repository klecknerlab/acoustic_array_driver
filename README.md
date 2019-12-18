# acoustic_array_driver

Firmware for an FPGA-based acoustic array driver, and an associated Python
driver.

## Firmware Installation

The code is made to run on a TinyFPGA BX.
To compile the firware, you will need apio and tinyprog (both can be installed
    with PIP).
Once you have the dependencies, the code can be compiled and uploaded with:

```shell
$ apio build
$ tinyprog -p build/aod_firmware.bin
```

These commands should be run from the firmware directory.

## Python Module Usage

The best way to use this is to install the code in developer mode.
After downloading the source, enter the main directory of the code, and install
the module in develop mode using the following command line argument:

```shell
$ python setup.py develop
```

In general, you should not modify the code in the source directory.  Rather,
you should be able to import the module from scripts in other directories
once it is globally installed.  (See examples directory.)

Once installed, you should have access to the `acoustic_array` module from a
script in any directory.  See the examples directory for... examples.

## Low Level Driver Information

All commands are 4 bytes, the first byte is always a command byte, followed by 3 one byte arguments.
If capitalized, the device will respond, otherwise nothing is returned.
Generally speaking, the reply will be a 1 byte error message (should be 0),
followed by the original command arguments.

Command Byte | Description | Argument 1 | Argument 2 | Argument 3
--- | --- | --- | --- | ---
`"w"` or `"W"` | Write one channel | Channel # | Duty (0-255) | Phase (0-255)
`"b"` or `"B"` | Select read/write bank | (ignored) | Write Bank (0-15)* | Read Bank (0-15)*
`"s"` or `"S"` | Swap Output Channels | Physical Channel (0-15) |  Virtual Channel on Odd Pins (0-15)* | Virtual Channel on Even Pins (0-15)*

* If requested channels are >15, no changes are made, but the current channel
is returned in the reply.
