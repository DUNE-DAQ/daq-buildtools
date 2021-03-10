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
            pexpect.EOF,
            pexpect.TIMEOUT
        ])

    while True:
        index = process.expect (patterns)

        # print(index)
        if index == 0:
            text=process.before.decode('utf-8')
            print(text)
            if log:
                print(text, file=logfile)

        elif index == 1:
            if not process.before:
                continue
            text=process.before.decode('utf-8')
            print(text)
            if log:
                print(text, file=logfile)
        else:
            break
    process.close()
    
    # print(process.exitstatus, process.signalstatus)
    raise SystemExit(process.exitstatus)

if __name__ == '__main__':
    run()