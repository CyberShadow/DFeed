DFeed
=====

DFeed is a multi-protocol news aggregator and forum system:

- NNTP client
- Mailing list archive
- Web-based forum interface
- ATOM feed aggregator
- IRC bot

## Demo Instance

A demo instance is available here: https://dfeed-demo.cy.md/

## Directory Structure

- `src/` - Application source code
- `site-defaults/` - Default configuration and web templates (tracked in repo)
- `site/` - Site-specific overrides (gitignored, your customizations go here)

Files in `site/` override files in `site-defaults/`. This allows you to customize
your installation without modifying tracked files.

## Quick Start

```bash
git clone --recursive https://github.com/CyberShadow/DFeed.git
cd DFeed
```

### Building with Dub (executable only)

```bash
dub build
```

### Building with Nix (executable and minified resources)

```bash
nix build .
```

### Configuration

Create your site-specific configuration in `site/`:

```bash
mkdir -p site/config/sources/nntp
cp site-defaults/config/site.ini.sample site/config/site.ini
# Edit site/config/site.ini with your settings

# Add an NNTP source:
echo "host = your.nntp.server" > site/config/sources/nntp/myserver.ini

# Configure web interface:
echo "listen.port = 80" > site/config/web.ini
```

### Running

```bash
./dfeed
```

On first start, DFeed downloads messages from configured NNTP servers.
Access the web interface at http://localhost:8080/.

## Site-Specific Deployments

For an example of a complete site-specific setup, see the
[dlang.org forum configuration](https://github.com/CyberShadow/d-programming-language.org/tree/dfeed/dfeed).
