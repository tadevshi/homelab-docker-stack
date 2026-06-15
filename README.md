# Homelab Docker Stack

A comprehensive Docker Compose stack for personal homelab services. This repository contains various self-hosted applications organized in separate directories for easy management and deployment.

## 🏗️ Architecture

The stack is organized into service-specific directories, each containing its own `docker-compose.yml` file. This modular approach allows for independent management of each service while maintaining a cohesive deployment strategy.

## 📋 Services Overview

### 📊 Monitoring & Management
- **Homepage** - Application dashboard and launcher
  - Port: 3001
  - Centralized access to all services
  - Real-time monitoring widgets
  - Data persistence: `/opt/docker-data/homepage`

- **Grafana** - Open-source analytics and monitoring platform
  - Port: 3000
  - Data persistence: `/opt/docker-data/grafana`
  
- **Portainer** - Container management web interface
  - Port: 9000
  - Docker socket access for container management
  - Data persistence: `/opt/docker-data/portainer`

### 🎬 Media Management
- **Plex** - Media server for organizing and streaming media (Smart TV apps, mobile, web)
  - Port: 32400
  - CPU-only transcoding (no GPU passthrough)
  - First-boot claim flow required (see First-time setup)
  - Read-write media access via `media/data/media`
  - Mounts `media/data/media` (ro) and uses host networking for DLNA

- **Jellyfin** - Media server alternative (open-source)
  - Network Mode: Host
  - Port: 8096
  - Media directory: `media/data/media` (read-only)
  - Persistent configuration and cache volumes

- **FileBrowser** - Web-based file manager for media, downloads, and the stack directory
  - Port: 8080
  - Default credentials: `admin` / `admin` — change on first login
  - Root: `/data` (configured via `FB_ROOT`)
  - Read-write access to `media/data/media`, `media/data/downloads`, and the stack directory

- **Media Stack** (Complete media management suite):
  - **Jackett** - Torrent indexer proxy (Port: 9117)
  - **Sonarr** - TV series management (Port: 8989)
  - **Radarr** - Movie management (Port: 7878)
  - **Transmission** - Torrent client (Port: 9091, 51413)
  - **FlareSolverr** - Cloudflare bypass proxy (Port: 8191)
    - Image: `ghcr.io/flaresolverr/flaresolverr:latest`
    - RAM: ~500 MB – 1 GB per browser instance (Chrome via Selenium)
    - Auto-configured by `media/bootstrap.sh` — no manual step required
    - Reference: https://github.com/FlareSolverr/FlareSolverr
  - **Bazarr** - Automatic subtitle manager (Port: 6767)
    - Image: `lscr.io/linuxserver/bazarr:latest`
    - Integrates with Sonarr/Radarr to download subtitles
    - Supports OpenSubtitles, Subscene, SubtitleCat, and more
  - Shared directories: `media/data/media`, `media/data/downloads`

### 🛠️ Productivity & Automation
- **n8n** - Workflow automation tool
  - Port: 5678
  - Basic authentication enabled
  - Runners enabled for enhanced performance

- **Excalidraw** - Virtual whiteboard for diagramming
  - Port: 5000
  - Collaborative drawing tool

### 🔒 Network & Security
- **Pi-hole** - DNS-based ad blocker
  - DNS Ports: 53 (TCP/UDP)
  - Web Interface: Custom port via `${PIHOLE_WEBPORT}`
  - DNS servers: 127.0.0.1, 1.1.1.1

## 🚀 Quick Start

### Prerequisites
- Docker and Docker Compose installed
- Sufficient disk space for persistent data
- Appropriate user permissions for Docker

### Environment Configuration
Create a `.env` file in the root directory with the following variables:

```bash
# Timezone
TZ=Europe/Madrid

# User/Group ID for container permissions (use `id -u` / `id -g`)
PUID=1000
PGID=1000

# Network Configuration
BASE_DOMAIN=local
HOMELAB_IP=192.168.x.x        # Replace with your server's IP

# n8n Authentication
N8N_BASIC_AUTH_USER=your_username
N8N_BASIC_AUTH_PASSWORD=your_password

# Pi-hole
PIHOLE_WEBPASSWORD=your_admin_password
PIHOLE_WEBPORT=8080
PIHOLE_API_KEY=your_pihole_api_key

# Homepage Services API Keys (Optional - for enhanced widgets)
GRAFANA_PASSWORD=your_grafana_password
JELLYFIN_API_KEY=your_jellyfin_api_key
SONARR_API_KEY=your_sonarr_api_key
RADARR_API_KEY=your_radarr_api_key
JACKETT_API_KEY=your_jackett_api_key
PORTAINER_ENDPOINT=your_portainer_endpoint
PORTAINER_API_KEY=your_portainer_api_key

# Plex (optional - if not set, claim via app.plex.tv)
# PLEX_CLAIM=claim-xxxxxxxxxxxx
```

> **Note:** Always use `--env-file .env` flag when running `docker compose` commands from the project root to ensure environment variables are loaded correctly.

### Directory Setup
Create required directories for persistent data and set permissions to match your `PUID`/`PGID`:

```bash
sudo mkdir -p /opt/docker-data/{grafana,portainer,homepage}
mkdir -p media/data/media/{movies,tv}
mkdir -p media/data/downloads/{complete,incomplete,torrents}

# Set ownership to match the PUID/PGID in your .env (e.g., 1000:1000)
sudo chown -R $USER:$USER /opt/docker-data
chown -R $(id -u):$(id -g) media/data
```

> If you don't have a non-root user with UID 1000, create one first:
> ```bash
> sudo useradd -m -u 1000 media
> sudo chown -R 1000:1000 media/data
> ```

### Deployment Options

#### Option 1: Individual Service Deployment
From the project root, use the env-file flag to load variables:
```bash
docker compose --env-file .env -f [service-directory]/docker-compose.yml up -d
```

#### Option 2: Automated Deployment (Recommended)
Use the provided deployment script:
```bash
chmod +x deploy.sh
./deploy.sh
```

The deployment script:
- Loads environment variables from `.env`
- Handles private registry authentication (if `~/.ghcr_env` exists)
- Pulls latest changes from Git
- Detects modified directories and rebuilds only changed services
- Automatically restarts updated services

## 🔧 Configuration Details

### Media Stack Integration
The media services are designed to work together:
1. **Jackett** searches and provides torrent trackers (via Torznab)
2. **Sonarr** monitors and downloads TV series
3. **Radarr** monitors and downloads movies
4. **Transmission** handles the actual torrent downloads
5. **Bazarr** automatically downloads subtitles for media files
6. **FlareSolverr** bypasses Cloudflare protection for Jackett indexers

All services share common download and media directories for seamless integration.

### Automatic Wiring (bootstrap.sh)
The `media/bootstrap.sh` script automatically configures the integration between services:
- Adds Transmission as a download client in Sonarr and Radarr
- Adds Jackett as a Torznab indexer in Sonarr and Radarr
- Sets up root folders (`/data/media/tv` for Sonarr, `/data/media/movies` for Radarr)
- Creates HD-1080p quality profiles
- Configures FlareSolverr URL in Jackett (with fallback to direct file edit if the API fails)

### Authentication & Security
- **n8n**: Basic authentication via environment variables
- **Pi-hole**: Admin interface password protected
- All services run with non-root user (PUID/PGID) where possible
- Plex: Configure `secureConnections` in Preferences.xml if you have SSL issues (see Troubleshooting)

## 📁 File Structure
```
homelab-docker-stack/
├── excalidraw/
│   └── docker-compose.yml
├── filebrowser/
│   └── docker-compose.yml
├── grafana/
│   └── docker-compose.yml
├── homepage/
│   ├── docker-compose.yml
│   └── settings.yaml
├── jellyfin/
│   └── docker-compose.yml
├── media/
│   ├── docker-compose.yml
│   ├── bootstrap.sh
│   └── data/
│       ├── .gitignore
│       ├── .gitkeep
│       ├── media/
│       │   ├── movies/
│       │   └── tv/
│       └── downloads/
│           ├── complete/
│           ├── incomplete/
│           └── torrents/
├── n8n/
│   └── docker-compose.yml
├── plex/
│   └── docker-compose.yml
├── pihole/
│   └── docker-compose.yml
├── portainer/
│   └── docker-compose.yml
├── .env.example
├── .gitignore
├── deploy.sh
└── README.md
```

## 🔄 Maintenance

### Updates
To update all services:
```bash
./deploy.sh
```

To update a specific service:
```bash
docker compose --env-file .env -f [service-directory]/docker-compose.yml pull
docker compose --env-file .env -f [service-directory]/docker-compose.yml up -d
```

### Backup
Regularly backup the persistent data directories:
- `/opt/docker-data/`
- `media/data/` (media files and downloads)
- Any custom configuration files

### Logs
View logs for any service:
```bash
docker compose --env-file .env -f [service-directory]/docker-compose.yml logs -f
```

## 🌐 Access URLs

After deployment, access services via `http://<HOMELAB_IP>:<port>` or `http://localhost:<port>`:

| Service | Port | URL |
|---------|------|-----|
| Homepage | 3001 | `http://<HOMELAB_IP>:3001` |
| Grafana | 3000 | `http://<HOMELAB_IP>:3000` |
| Portainer | 9000 | `http://<HOMELAB_IP>:9000` |
| n8n | 5678 | `http://<HOMELAB_IP>:5678` |
| Jellyfin | 8096 | `http://<HOMELAB_IP>:8096` |
| Plex | 32400 | `http://<HOMELAB_IP>:32400/web` |
| FileBrowser | 8080 | `http://<HOMELAB_IP>:8080` |
| Excalidraw | 5000 | `http://<HOMELAB_IP>:5000` |
| Pi-hole | `${PIHOLE_WEBPORT}` | `http://<HOMELAB_IP>:${PIHOLE_WEBPORT}/admin` |
| Jackett | 9117 | `http://<HOMELAB_IP>:9117` |
| Sonarr | 8989 | `http://<HOMELAB_IP>:8989` |
| Radarr | 7878 | `http://<HOMELAB_IP>:7878` |
| Transmission | 9091 | `http://<HOMELAB_IP>:9091` |
| FlareSolverr | 8191 | `http://<HOMELAB_IP>:8191` (health: `/health`) |
| Bazarr | 6767 | `http://<HOMELAB_IP>:6767` |

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## ⚠️ Important Notes

- Ensure proper firewall configuration for exposed ports
- Regularly update container images for security
- Backup configuration data before major updates
- Monitor disk space usage, especially for media and torrent directories
- Some services require additional initial configuration through their web interfaces
- For external access (outside your LAN), configure port forwarding on your router (see Plex section)

## 🆘 Troubleshooting

### Common Issues
1. **Port conflicts**: Check if ports are already in use with `ss -tlnp`
2. **Permission errors**: Verify `PUID`/`PGID` settings in `.env` match the directory owner (`id -u`/`id -g`)
3. **DNS issues**: Ensure local DNS resolution for `.local` domains
4. **Volume mounting**: Verify directory paths and permissions
5. **Environment variables not loading**: Use `--env-file .env` flag explicitly when running `docker compose` from the project root

### Plex: "No se puede conectar al servidor de forma segura"
Plex requires HTTPS by default. For LAN-only access, edit the preferences:
```bash
docker exec plex sed -i 's/secureConnections="[0-9]*"/secureConnections="1"/' \
  "/config/Library/Application Support/Plex Media Server/Preferences.xml"
docker restart plex
```
- `secureConnections="1"` allows both HTTP and HTTPS (recommended for LAN)
- `secureConnections="0"` allows only HTTP
- `secureConnections="2"` requires HTTPS only (default)

### Plex: Server not visible from app.plex.tv or Smart TV
If your router doesn't support UPnP/NAT-PMP, configure port forwarding manually:
- **External port**: 32400
- **Internal port**: 32400
- **Protocol**: TCP
- **Destination IP**: `<HOMELAB_IP>`

Then edit Preferences.xml to enable publishing:
```bash
docker exec plex sed -i 's/PublishServerOnPlexOnlineKey="0"/PublishServerOnPlexOnlineKey="1"/' \
  "/config/Library/Application Support/Plex Media Server/Preferences.xml"
docker restart plex
```

### Jellyfin: Login screen appears but no user can be created
If the startup wizard was completed without creating a user, reset it:
```bash
docker exec jellyfin sed -i 's/<IsStartupWizardCompleted>true<\/IsStartupWizardCompleted>/<IsStartupWizardCompleted>false<\/IsStartupWizardCompleted>/' \
  /config/config/system.xml
docker restart jellyfin
```
Then access `http://<HOMELAB_IP>:8096` and complete the wizard.

### Transmission: Downloads not appearing in the right folder
If Transmission ignores the `TRANSMISSION_DOWNLOAD_DIR` env var (because a `settings.json` already exists), edit it directly:
```bash
docker stop transmission
docker run --rm -v <volume_name>:/config alpine sh -c \
  "sed -i 's|/downloads/complete|/data/downloads/complete|g; s|/downloads/incomplete|/data/downloads/incomplete|g' /config/settings.json"
docker start transmission
```
The volume name is typically `media_transmission_config`.

### Jackett: FlareSolverr not configured
The Jackett API may return a 302 redirect instead of JSON. The `bootstrap.sh` handles this by editing the config file directly. If FlareSolverr is still not set:
```bash
docker exec jackett sh -c \
  'sed -i "s|\"FlareSolverrUrl\": *null|\"FlareSolverrUrl\": \"http://flaresolverr:8191/\"|; s|\"FlareSolverrUrl\": *\"[^\"]*\"|\"FlareSolverrUrl\": \"http://flaresolverr:8191/\"|" \
  /config/Jackett/ServerConfig.json'
docker restart jackett
```

### FileBrowser: Permission denied on file upload
If `/data/media` is mounted read-only, change it to read-write in `filebrowser/docker-compose.yml`:
```yaml
- ../media/data/media:/data/media:rw   # was :ro
```
Then recreate the container:
```bash
docker compose --env-file .env -f filebrowser/docker-compose.yml up -d --force-recreate
```

### Getting Help
- Check container logs: `docker logs [container-name]`
- Verify service status: `docker ps`
- Check system resources: `docker system df`
- Inspect a running container: `docker exec -it [container-name] sh`

## 🚀 First-time setup

Follow these steps in order to get the entire media pipeline running end-to-end.

### 1. Configure environment and directories
```bash
# Copy and edit the env file
cp .env.example .env
nano .env   # Set PUID, PGID, HOMELAB_IP, passwords, etc.

# Create directories and set permissions
mkdir -p media/data/media/{movies,tv}
mkdir -p media/data/downloads/{complete,incomplete,torrents}
chown -R $(id -u):$(id -g) media/data
```

### 2. Start the media stack
```bash
docker compose --env-file .env -f media/docker-compose.yml up -d
```
This brings up: Jackett, Sonarr, Radarr, Transmission, FlareSolverr, and Bazarr.

### 3. Start Plex
```bash
docker compose --env-file .env -f plex/docker-compose.yml up -d
```

**Option A — Claim via the `PLEX_CLAIM` env var (recommended):**
1. Get a claim token from https://app.plex.tv/claim
2. Set `PLEX_CLAIM=claim-xxxxxxxxxxxx` in your `.env`
3. Recreate the container: `docker compose --env-file .env -f plex/docker-compose.yml up -d --force-recreate`

**Option B — Claim from the logs:**
1. Watch the logs: `docker logs -f plex`
2. Look for `Plex claim token: claim-xxxxxxxxxxxx` (window ~4 minutes)
3. Open https://app.plex.tv/claim and paste the token

### 4. Start FileBrowser
```bash
docker compose --env-file .env -f filebrowser/docker-compose.yml up -d
```
Open `http://<HOMELAB_IP>:8080` and log in with `admin` / `admin`. **Change the password immediately.**

FileBrowser exposes:
- `/data/media` — Movies and TV libraries (read-write for uploads)
- `/data/downloads` — Completed/incomplete torrents
- `/data/stack` — The homelab-docker-stack project directory

### 5. Start Jellyfin
```bash
docker compose --env-file .env -f jellyfin/docker-compose.yml up -d
```
Open `http://<HOMELAB_IP>:8096` and complete the initial setup wizard. If the wizard is already marked complete but no user exists, see the Troubleshooting section to reset it.

### 6. Gather API keys
Open each web UI and copy the API key:
- **Sonarr**: `http://<HOMELAB_IP>:8989` → Settings > General > API Key
- **Radarr**: `http://<HOMELAB_IP>:7878` → Settings > General > API Key
- **Jackett**: `http://<HOMELAB_IP>:9117` → top-right key icon → API Key

### 7. Run the bootstrap script
This wires all media services together automatically:
```bash
SONARR_API_KEY=<your-sonarr-key> \
RADARR_API_KEY=<your-radarr-key> \
JACKETT_API_KEY=<your-jackett-key> \
./media/bootstrap.sh
```
The script is idempotent — re-running it is safe. It configures:
- Transmission as a download client in Sonarr and Radarr
- Jackett as a Torznab indexer in Sonarr and Radarr
- Root folders: `/data/media/tv` (Sonarr), `/data/media/movies` (Radarr)
- HD-1080p quality profiles
- FlareSolverr URL in Jackett (with config-file fallback if the API fails)

To also add each Jackett indexer individually (not just the generic `all` indexer), pass `--jackett-indexers`:
```bash
./media/bootstrap.sh --jackett-indexers
```

### 8. Add libraries in Plex and Jellyfin

**Plex** (`http://<HOMELAB_IP>:32400/web`):
- Add a **Movies** library pointing to `/data/media/movies`
- Add a **TV Shows** library pointing to `/data/media/tv`
- Run a library scan

**Jellyfin** (`http://<HOMELAB_IP>:8096` → Dashboard > Libraries):
- Add a **Movies** library pointing to `/data/media/movies`
- Add a **TV Shows** library pointing to `/data/media/tv`
- Run a library scan

### 9. Configure Bazarr (subtitles)
1. Open `http://<HOMELAB_IP>:6767` and log in (configure the admin password on first run)
2. **Settings > Sonarr**: Add connection with host `sonarr`, port `8989`, and your Sonarr API key
3. **Settings > Radarr**: Add connection with host `radarr`, port `7878`, and your Radarr API key
4. **Settings > Languages**: Select your preferred subtitle languages
5. **Settings > Providers**: Enable at least one provider:
   - **OpenSubtitles** (requires free account at https://www.opensubtitles.com)
   - **SubtitleCat** (no account required)
   - **Subscene** (works with FlareSolverr, already configured)
6. **Settings > FlareSolverr**: Set URL to `http://flaresolverr:8191/` to bypass Cloudflare

Bazarr will automatically scan your media libraries and download matching subtitles.

### 10. End-to-end smoke test
**In Sonarr:**
1. Add a series (use a public-domain title or one you have rights to)
2. Search for an episode
3. Confirm the torrent is sent to Transmission

**In Transmission** (`http://<HOMELAB_IP>:9091`):
1. Confirm the torrent appears and begins downloading
2. Wait for completion

**In Sonarr:**
1. Confirm the completed file is imported to `/data/media/tv/<series>/<season>/...`

**In Bazarr:**
1. Confirm subtitles are downloaded for the new media

**In Plex / Jellyfin:**
1. Confirm the new media is detected and playable

**On the host, verify:**
```bash
ls media/data/media/tv/
ls media/data/media/movies/
ls media/data/downloads/complete/
```

### 11. (Optional) External access
For accessing Plex/Jellyfin from outside your LAN:
1. **Port forwarding on your router**:
   - Plex: TCP 32400 → `<HOMELAB_IP>:32400`
   - Jellyfin: TCP 8096 → `<HOMELAB_IP>:8096`
2. **Plex**: Edit `Preferences.xml` to enable publishing (see Troubleshooting)
3. **Jellyfin**: Settings > Remote Access → Enable

> For security, consider using a reverse proxy (Caddy, Nginx, Traefik) with HTTPS for external access.
