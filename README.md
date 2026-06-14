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
  - Read-only media access via `media/data/media`

- **Jellyfin** - Media server alternative (open-source)
  - Network Mode: Host
  - Media directory: `media/data/media` (read-only)
  - Persistent configuration and cache volumes

- **FileBrowser** - Web-based file manager for media and download directories
  - Port: 8080
  - Default credentials: `admin` / `admin` — change on first login
  - Read-only access to `media/data/media`; read-write access to `media/data/downloads`

- **Media Stack** (Complete media management suite):
  - **Jackett** - Torrent indexer proxy (Port: 9117)
  - **Sonarr** - TV series management (Port: 8989)
  - **Radarr** - Movie management (Port: 7878)
  - **Transmission** - Torrent client (Port: 9091, 51413)
  - **FlareSolverr** - Cloudflare bypass proxy for Jackett (Port: 8191)
    - Image: `ghcr.io/flaresolverr/flaresolverr:latest`
    - RAM: ~500 MB – 1 GB per browser instance (Chrome via Selenium)
    - Auto-configured by `media/bootstrap.sh` — no manual step required
    - Reference: https://github.com/FlareSolverr/FlareSolverr
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

# User/Group ID for container permissions
PUID=1000
PGID=1000

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
```

### Directory Setup
Create required directories for persistent data:

```bash
sudo mkdir -p /opt/docker-data/{grafana,portainer,homepage}
mkdir -p media/data/media/{movies,tv}
mkdir -p media/data/downloads/{complete,incomplete,torrents}
sudo chown -R $USER:$USER /opt/docker-data
```

### Deployment Options

#### Option 1: Individual Service Deployment
Navigate to any service directory and run:
```bash
cd [service-directory]
docker-compose up -d
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
1. **Jackett** searches and provides torrent trackers
2. **Sonarr** monitors and downloads TV series
3. **Radarr** monitors and downloads movies
4. **Transmission** handles the actual torrent downloads

All services share common download and media directories for seamless integration.

### Authentication & Security
- **n8n**: Basic authentication via environment variables
- **Pi-hole**: Admin interface password protected
- All services run with non-root user where possible

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
cd [service-directory]
docker-compose pull
docker-compose up -d
```

### Backup
Regularly backup the persistent data directories:
- `/opt/docker-data/`
- Any custom configuration files

### Logs
View logs for any service:
```bash
docker-compose -f [service-directory]/docker-compose.yml logs -f
```

## 🌐 Access URLs

After deployment, access services via:
- **Homepage**: `http://localhost:3001` (main dashboard)
- **Grafana**: `http://localhost:3000`
- **Portainer**: `http://localhost:9000`
- **n8n**: `http://localhost:5678`
- **Jellyfin**: `http://localhost:8096`
- **Plex**: `http://localhost:32400/web`
- **FileBrowser**: `http://localhost:8080`
- **Excalidraw**: `http://localhost:5000`
- **Pi-hole**: `http://localhost:${PIHOLE_WEBPORT}/admin`
- **Jackett**: `http://localhost:9117`
- **Sonarr**: `http://localhost:8989`
- **Radarr**: `http://localhost:7878`
- **Transmission**: `http://localhost:9091`
- **FlareSolverr**: `http://localhost:8191` (health: `/health`)

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

## 🆘 Troubleshooting

### Common Issues
1. **Port conflicts**: Check if ports are already in use
2. **Permission errors**: Verify user ID/GID settings in `.env`
3. **DNS issues**: Ensure local DNS resolution for `.local` domains
4. **Volume mounting**: Verify directory paths and permissions

### Getting Help
- Check container logs: `docker logs [container-name]`
- Verify service status: `docker ps`
- Check system resources: `docker system df`

## 🚀 First-time setup

Follow these steps in order to get the media pipeline running end-to-end.

### 1. Start the media stack
```bash
docker compose -f media/docker-compose.yml up -d
```

### 2. Start Plex
```bash
docker compose -f plex/docker-compose.yml up -d
```
Watch the logs for the claim URL:
```bash
docker logs -f plex
```
You will see a line like `Plex claim token: claim-xxxxxxxxxxxx`. Copy the full `claim-...` URL. You have ~4 minutes to complete step 3.

### 3. Claim Plex
Open `https://app.plex.tv/claim` in a browser and sign in with your Plex account. Paste the claim token from the logs. Your Plex server will now be linked to your account.

### 4. Start FileBrowser
```bash
docker compose -f filebrowser/docker-compose.yml up -d
```
Open `http://localhost:8080` and log in with `admin` / `admin`. You will be prompted to change the password — do this immediately.

### 5. Start Jellyfin
```bash
docker compose -f jellyfin/docker-compose.yml up -d
```

### 6. Gather API keys
Open each web UI and copy the API key from **Settings > General**:
- Sonarr: `http://localhost:8989` → Settings > General → API Key
- Radarr: `http://localhost:7878` → Settings > General → API Key
- Jackett: `http://localhost:9117` → top-right key icon → API Key

### 7. Run the bootstrap script
```bash
SONARR_API_KEY=<your-sonarr-key> \
RADARR_API_KEY=<your-radarr-key> \
JACKETT_API_KEY=<your-jackett-key> \
./media/bootstrap.sh
```
This wires Transmission and Jackett into Sonarr and Radarr automatically. The script also writes Jackett's global FlareSolverr URL automatically (after indexer registration, before root folders are created). The script is idempotent — re-running it is safe.

### 8. Add libraries in Plex and Jellyfin
In the **Plex** web UI:
- Add a **Movies** library pointing to `/data/media/movies`
- Add a **TV Shows** library pointing to `/data/media/tv`

In the **Jellyfin** web UI (Dashboard > Libraries):
- Add a **Movies** library pointing to `/data/media/movies`
- Add a **TV Shows** library pointing to `/data/media/tv`

Run a library scan in both UIs to confirm media is detected.

### 9. End-to-end smoke test
In **Sonarr**:
1. Add a series (use a public-domain title or one you have rights to)
2. Search for an episode
3. Confirm the torrent is sent to Transmission

In **Transmission** (`http://localhost:9091`):
1. Confirm the torrent appears and begins downloading
2. Wait for completion

In **Sonarr**:
1. Confirm the completed file is imported to `/data/media/tv/<series>/<season>/...`

On the host, verify:
```bash
ls media/data/media/tv/
ls media/data/downloads/complete/
```