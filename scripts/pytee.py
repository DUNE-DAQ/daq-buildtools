#!/usr/bin/env python

import pexpect
import click
import shutil



@click.command()
@click.argument('cmd')
@click.argument('args', nargs=-1)
@click.option('-l', '--log', type=click.Path(), help='Log file.')
def run(cmd, args, log):
    """
    Execute CMD with argument ARGS in a subshell with pty.
    
    CMD: The command.  

    ARGS: The command arguments.
    """
    # print(cmd, args, log)

    if not pexpect.which(cmd):
        raise click.UsageError(f"ERROR: Command '{cmd}' not found.")

    logfile = None
    if log:
        logfile = open(log,'w')


    cols, rows = shutil.get_terminal_size(fallback=(400, 100))

    process = pexpect.spawn(
        f'{cmd} {" ".join(args)}',
        dimensions=(rows, cols)
    )

    patterns = process.compile_pattern_list([
            '\r\n',
            '\r',
            pexpect.TIMEOUT,
            pexpect.EOF,
        ])

    while True:
        index = process.expect (patterns, timeout=60)

        # Newline
        if index == 0:
            text=process.before.decode('utf-8')
            print(text,flush=True)
            if log:
                print(text, file=logfile)

        # Carriage return
        elif index == 1:
            if not process.before:
                continue
            text=process.before.decode('utf-8')
            print(text,flush=True)
            if log:
                print(text, file=logfile)
        # Timeout
        elif index == 2:
            print('<pytee: 60 sec elapsed without new input>')
            continue
        else:
            break
    process.close()
    
    # print(process.exitstatus, process.signalstatus)
    raise SystemExit(process.exitstatus)

if __name__ == '__main__':
    run()
