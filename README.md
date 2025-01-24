## zduel

[![GPLv3 License](https://img.shields.io/badge/License-GPL%20v3-yellow.svg)](https://opensource.org/licenses/)

A command-line chess tool for playing and analyzing chess games, with support for multiple engines and tournament organization.

## Features

### Current
- Interactive command-line interface
- Cross-platform support (Windows, macOS, Linux)
- Built-in documentation browser
- Engine management system

### Planned
- Support for multiple chess engines
- Engine vs engine matches
- Custom engine configuration
- Tournament organization between multiple engines

## Installation

```bash
# Installation instructions coming soon
```

## Usage

Basic commands:

```bash
zduel              # Start interactive mode
zduel help         # Display help information
zduel docs         # Open documentation in browser
zduel engines      # Manage chess engines
```

## Engine Management

The `engines` command provides the following subcommands:
- `list`: View installed engines
- `add`: Add a new engine
- `remove`: Remove an installed engine

## Development

zduel is written in Zig and is under active development. The project structure is organized as follows:

```
zduel/
├── src/
│   ├── main.zig    # Entry point
│   └── cli.zig     # CLI implementation
```

### Building from Source

```bash
# Build instructions coming soon
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

[License information pending]

## Documentation

Full documentation is available at [https://zduel-docs.vercel.app/](https://zduel-docs.vercel.app/)
