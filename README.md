# Homelab Docker Stack

A comprehensive Docker Compose stack for personal homelab services. This repository contains various self-hosted applications organized in separate directories for easy management and deployment. Tailscale is included for secure remote access to the homelab without exposing ports.

## 🏗️ Architecture

The stack is organized into service-specific directories, each containing its own `docker-compose.yml` file. This modular approach allows for independent management of each service while maintaining a cohesive deployment strategy.

Tailscale runs as an additional standalone container that authenticates with your Tailscale account via an auth key (`TS_AUTHKEY`) in your environment.

## 📋 Services Overview

### 🔍 Monitoring & Management
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

### 🔐 Network & Security (NEW — Tailscale)
- **Tailscale** - Secure virtual private network for remote access
  - Runs as a standalone Docker container
  - Authenticates with your Tailscale account via auth key (`TS_AUTHKEY`)
  - Connects all your homelab services to your tailnet, allowing secure remote access without port forwarding
  - Access any service from anywhere using `https://<hostname>.tailnet.com`

### 🛠️ Productivity & Automation
- **n8n** - Workflow automation tool
  - Port: 5678
  - Basic authentication enabled
  - Runners enabled for enhanced performance

- **Excalidraw** - Virtual whiteboard for diagramming
  - Port: 5000
  - Collaborative drawing tool

## 🚀 Quick Start

### Prerequisites
- Docker and Docker Compose installed
- Sufficient disk space for persistent data
- Appropriate user permissions for Docker
- A Tailscale account with permission to generate auth keys from the admin console (https://console.tailscale.com)

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

# Tailscale Authentication
TS_AUTHKEY=<tskey-YOUR-AUTH-KEY>  # Get from https://console.tailscale.com/admin/settings/keys

# n8n Authentication
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=change-me-please

# Jellyfin (optional - claim token if needed)
JELLYFIN_API_KEY=<your-jellyfin-api-key>
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

### Tailscale Setup
After generating your auth key:
1. Set `TS_AUTHKEY=<your-key>` in `.env`
2. Run the deployment script or deploy manually:
   ```bash
   docker compose --env-file .env -f tailscale/docker-compose.yml up -d
   ```
3. Visit https://console.tailscale.com to verify `homelab-ts` appears

From any device connected to your tailnet, access services via their hostname (e.g., `https://jellyfin.homelab-ts.tailnet.com`)

### Authentication & Security
- **n8n**: Basic authentication via environment variables
- **Tailscale**: Authenticated using auth key from `TS_AUTHKEY`
- All services run with non-root user (PUID/PGID) where possible
- Plex: Configure `secureConnections` in Preferences.xml if you have SSL issues (see Troubleshooting)

## 📁 File Structure

```
homelab-docker-stack/
├── .env.example          # Variables template (secrets by default)
├── deploy.sh             # Automated deployment script
├── cleanup.sh            # Maintenance and cleanup utilities
├── README.md             # This file
├── excalidraw/           # Virtual whiteboard
│   └── docker-compose.yml
├── filebrowser/          # Web-based file manager
│   └── docker-compose.yml
├── grafana/              # Grafana + dashboards
│   └── docker-compose.yml
├── homepage/             # Application dashboard and launcher
│   ├── docker-compose.yml
│   └── settings.yaml
├── jellyfin/             # Jellyfin media server
│   └── docker-compose.yml
├── media/                # Media management stack (6 services)
│   ├── docker-compose.yml
│   ├── bootstrap.sh      # Auto-wires Sonarr, Radarr, Jackett, Transmission
│   ├── data/             # Persistent data directories
│   │   ├── .gitignore
│   │   ├── .gitkeep
│   │   ├── media/        # Movies and TV shows
│   │   │   ├── movies/
│   │   │   └── tv/
│   │   └── downloads/    # Completed, incomplete, torrents
│   └── .env.example      # Media-specific environment vars
├── n8n/                  # Workflow automation
│   └── docker-compose.yml
├── portainer/            # Portainer container management
│   └── docker-compose.yml
├── tailscale/            # Tailscale (NEW)
│   └── docker-compose.yml
├── .gitignore
└── LICENSE               # MIT License
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

### Logs
View logs for any service:
```bash
docker compose --env-file .env -f [service-directory]/docker-compose.yml logs -f
```

### Tailscale
Check Tailscale status:
```bash
docker logs tailscale-homelab
```

Visit https://console.tailscale.com to manage your network and access services from anywhere.

## 🌐 Access URLs

After deployment, access services via `http://<HOMELAB_IP>:<port>` or `http://localhost:<port>`. Once connected to your tailnet, you can also reach any service using its hostname:

| Service | Port | Local URL | Tailscale URL |
|---------|------|-----------|---------------|
| Homepage | 3001 | `http://<HOMELAB_IP>:3001` | `https://homelab-ts.tailnet.com` |
| Grafana | 3000 | `http://<HOMELAB_IP>:3000` | `https://grafana.homelab-ts.tailnet.com` |
| Portainer | 9000 | `http://<HOMELAB_IP>:9000` | `https://portainer.homelab-ts.tailnet.com` |
| n8n | 5678 | `http://<HOMELAB_IP>:5678` | `https://n8n.homelab-ts.tailnet.com` |
| Jellyfin | 8096 | `http://<HOMELAB_IP>:8096` | `https://jellyfin.homelab-ts.tailnet.com` |
| FileBrowser | 8080 | `http://<HOMELAB_IP>:8080` | `https://filebrowser.homelab-ts.tailnet.com` |
| Excalidraw | 5000 | `http://<HOMELAB_IP>:5000` | `https://excalidraw.homelab-ts.tailnet.com` |
| Jackett | 9117 | `http://<HOMELAB_IP>:9117` | `https://jackett.homelab-ts.tailnet.com` |
| Sonarr | 8989 | `http://<HOMELAB_IP>:8989` | `https://sonarr.homelab-ts.tailnet.com` |
| Radarr | 7878 | `http://<HOMELAB_IP>:7878` | `https://radarr.homelab-ts.tailnet.com` |
| Transmission | 9091 | `http://<HOMELAB_IP>:9091` | N/A (internal) |

> **Note:** Tailscale service URLs use the hostname set in `docker-compose.yml` (`homelab-ts`) + `.tailnet.com`. Make sure your Tailscale node name is set correctly.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License — see the LICENSE file for details.

## ⚠️ Important Notes

- Ensure proper firewall configuration if you need external access to services (though Tailscale makes this unnecessary)
- Regularly update container images for security
- Backup configuration data before major updates
- Monitor disk space usage, especially for media and torrent directories
- Some services require initial setup through their web interfaces

## 🆘 Troubleshooting

### Tailscale Issues

**"TS_AUTHKEY not set"** — Set the auth key in `.env`:
```bash
export TS_AUTHKEY=tskey-YOUR-AUTH-KEY
```

**"Unable to connect to tailnet"** — Check that:
1. The `TS_AUTHKEY` is valid and has permission for `homelab-ts`
2. Your Tailscale container is running (`docker ps`)
3. You're not on a mobile network (some networks block Tailscale)

**"Node not showing in console"** — Check logs:
```bash
docker logs tailscale-homelab
```

### Port Conflicts
Check if ports are already in use with `ss -tlnp` or `lsof -i :PORT`.

### Permission Errors
Verify `PUID`/`PGID` settings in `.env` match the directory owner (`id -u`/`id -g`). Ensure proper ownership on data directories.

## 🚀 First-time setup

Follow these steps in order to get the entire homelab running end-to-end:

### 1. Configure environment and directories
```bash
cp .env.example .env
nano .env   # Set PUID, PGID, HOMELAB_IP, TS_AUTHKEY, passwords, etc.

mkdir -p /opt/docker-data/{grafana,portainer,homepage}
mkdir -p media/data/media/{movies,tv}
mkdir -p media/data/downloads/{complete,incomplete,torrents}

sudo chown -R $USER:$USER /opt/docker-data
chown -R $(id -u):$(id -g) media/data
```

### 2. Start Tailscale (NEW — remote access)
```bash
docker compose --env-file .env -f tailscale/docker-compose.yml up -d
```
Then visit https://console.tailscale.com to verify `homelab-ts` appears. This gives you secure remote access to all your services without exposing ports.

### 3. Start Jellyfin
```bash
docker compose --env-file .env -f jellyfin/docker-compose.yml up -d
```
Open `http://<HOMELAB_IP>:8096` and complete the initial setup wizard. If the wizard is already marked complete but no user exists, see the Troubleshooting section to reset it.

### 4. Start FileBrowser
```bash
docker compose --env-file .env -f filebrowser/docker-compose.yml up -d
```
Open `http://<HOMELAB_IP>:8080` and log in with `admin` / `admin`. **Change the password immediately.**

FileBrowser exposes:
- `/data/media` — Movies and TV libraries (read-write for uploads)
- `/data/downloads` — Completed/incomplete torrents
- `/data/stack` — The homelab-docker-stack project directory

### 5. Start n8n and Excalidraw
```bash
docker compose --env-file .env -f n8n/docker-compose.yml up -d
docker compose --env-file .env -f excalidraw/docker-compose.yml up -d
```

### 6. Run the media bootstrap script
This wires all media services together automatically:
```bash
SONARR_API_KEY=<your-sonarr-key> \
RADARR_API_KEY=<your-radarr-key> \
JACKETT_API_KEY=<your-jackett-key> \
./media/bootstrap.sh
```

### 7. Add libraries in Jellyfin
**Jellyfin** (`http://<HOMELAB_IP>:8096` → Dashboard > Libraries):
- Add a **Movies** library pointing to `/data/media/movies`
- Add a **TV Shows** library pointing to `/data/media/tv`
- Run a library scan

### 8. End-to-end smoke test
Verify your homelab is working:
```bash
# Check all services are running
docker ps | grep -E "jellyfin|filebrowser|n8n|excalidraw"

# Test Tailscale connectivity (from a device on the tailnet)
curl https://<tailscale-node-name>.tailnet.com

# Test media stack integration
ls media/data/media/
ls media/data/downloads/complete/
```

### 9. (Optional) Verify remote access via Tailscale
From any device connected to your Tailscale network:
- Open a browser and navigate to `https://<service-name>.tailnet.com`
- Example: `https://jellyfin.homelab-ts.tailnet.com`

---

## 📝 Notes on Changes Made

1. **Added Tailscale** — New `tailscale/` directory with Docker Compose configuration for secure remote access to the homelab. No port forwarding required; just connect via your tailnet network.

2. **Removed Pi-hole** — Deleted the `pihole/` directory and its `docker-compose.yml`. This service was no longer being used.

3. **Removed Plex** — Deleted the `plex/` directory and its `docker-compose.yml`. This service is no longer part of the stack (Jellyfin remains).

---