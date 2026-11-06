import Foundation

// Line-buffered stdout, even into a file or a pipe (fully buffered there by default): `--watch` prints moments as
// they happen, and a run that is stopped (kill, Ctrl-C) must not lose what it already printed.
setvbuf(stdout, nil, _IOLBF, 0)

// Prints the live snapshot as JSON (spec §4). See `HeadroomDump` for the flags.
exit(HeadroomDump.run(arguments: Array(CommandLine.arguments.dropFirst())))
