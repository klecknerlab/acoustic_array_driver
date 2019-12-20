import traceback
import acoustic_array

controller = acoustic_array.Controller()

# controller.port.__enter__()

print('Syntax: [cmd] [val1] [val2] [val3]\n   cmd: single character, val1-3: 0-255')

while True:
    try:
        inp = input(str(controller.port) + '> ').strip()
        vals = []
        for i, part in enumerate(inp.split()):
            if i:
                vals.append(int(part))
            else:
                cmd = part.encode('utf-8')
                if len(cmd) != 1:
                    print()
        if len(cmd) != 1:
            print('ERROR: Command should be single byte!')
        if len(vals) > 3:
            print('ERROR: Maximum of three arguments')
        # print(repr(cmd), vals)

        reply = controller.cmd(cmd, *vals)
        if reply is not None:
            print(', '.join(map(str, reply)))

    except KeyboardInterrupt:
        break
    except:
        traceback.print_exc()

# controller.port.__exit__()
