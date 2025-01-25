# zduel

[![GPLv3 License](https://img.shields.io/badge/License-GPL%20v3-yellow.svg)](https://opensource.org/licenses/)

A command-line chess tool for managing engine matches and tournaments, with a focus on engine vs engine gameplay.

## Features

- Interactive CLI interface with color-coded output
- Engine vs engine matches with multiple time controls
- Real-time chess board visualization
- Match logging and analysis
- Cross-platform support (Windows, macOS, Linux)

## Installation

### Prerequisites
- Zig 0.14.0 or later
- Chess engines (UCI compatible)

### Building from Source
```bash
git clone https://github.com/strvdr/zduel.git
cd zduel
zig build
```

The executable will be available at `zig-out/bin/zduel`.

## Usage

### Interactive Mode

Execute the following command from the project root. If you fail to run zduel from the root of the project, it won't be able to find engines in the "engines" folder. 
```bash
./zig-out/bin/zduel
```
### Engine Setup
1. Create an `engines` directory in your zduel folder
2. Place UCI-compatible chess engines in the directory
3. Use `engines` command to manage them

If you don't have any chess engines installed, I recommend my engines [Kirin(C)](https://github.com/strvdr/kirin-v0) and [Kirin(Zig)](https://github.com/strvdr/kirin-chess) as a place to start. They are both UCI compatible chess engines in the ~2000 elo range. 

### Available Commands
- `help` - Display commands and usage
- `docs` - Open documentation in browser
- `engines` - Manage chess engines
- `match` - Start an engine vs engine match

### Match Types
- Blitz (1 second per move)
- Rapid (5 seconds per move)  
- Classical (15 seconds per move)
- Tournament (Best of 3 rapid games)

## Project Structure
```
zduel/
├── src/
│   ├── main.zig       # Entry point
│   ├── cli.zig        # CLI interface
│   ├── enginePlay.wig # Engine management
│   ├── engineMatch.zig # Match handling
│   ├── displayManager.zig # Board visualization
│   └── logger.zig     # Match logging
├── docs/
├── logs/

```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## License

This project is licensed under the GPLv3 License - see the LICENSE file for details.

## Documentation

Full documentation available at [https://zduel.strydr.net](https://zduel.strydr.net)
