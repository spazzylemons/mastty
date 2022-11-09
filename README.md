# mastty

mastty is a work-in-progress CLI client for [Mastodon](https://joinmastodon.org).

## Building

You will need:

- The lastest version of [Zig](https://ziglang.org)
- [zigmod](https://github.com/nektro/zigmod)
- [OpenSSL](https://www.openssl.org/)
- [GNU Readline](https://git.savannah.gnu.org/cgit/readline.git)

To download dependencies, run `zigmod fetch`. Then run `zig build` to build a debug build,
`zig build -Drelease-fast` for a speed-optimized build, or `zig build -Drelease-small` for a
size-optimized build. The executable is at `zig-out/bin/mastty`.

## Usage

Not much to say here as there isn't much implemented yet. Running the program prompts for
authorization if needed, then lets you send a post. A more advanced interface is coming soon.

Note: mastty is only written with Linux support at the moment. Support for Windows via MinGW is
planned.

## License

mastty is licensed under the GNU General Public License, either [version 3](LICENSE), or (at your
option) any later version.
