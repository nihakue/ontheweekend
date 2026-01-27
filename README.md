# On The Weekend

Internet radio station infrastructure - icecast server with scheduled show playback.

## Features

- Icecast streaming server with HTTPS via Caddy
- Web UI for scheduling shows (Saturday evening, Sunday morning slots)
- Automatic show playback via systemd timers
- Silence fallback stream with instant switchover when shows start

## Quick Start (Oracle Cloud)

1. Create a VCN (Virtual Cloud Network)
2. Create an Internet Gateway, attach to VCN
3. Add route rule to default route table: destination `0.0.0.0/0` → Internet Gateway
4. Create a public subnet in the VCN
5. Add ingress rules to the subnet's security list:
   - `0.0.0.0/0` TCP port 22 (SSH)
   - `0.0.0.0/0` TCP port 80 (HTTP)
   - `0.0.0.0/0` TCP port 443 (HTTPS)
6. Create a compute instance (Ubuntu) in the public subnet
7. Set up SSH config for easy access:
   ```
   # ~/.ssh/config
   Host ontheweekend
       HostName <your-domain-or-ip>
       User ubuntu
   ```
8. Copy `.env.template` to `.env` and fill in the values:
   ```bash
   cp .env.template .env
   # Edit .env with your passwords and domain
   ```
9. Generate the Caddy password hash:
   ```bash
   caddy hash-password --plaintext 'yourpassword'
   # Add the output to SCHEDULE_PASSWORD_HASH in .env
   ```
10. Run `./radio bootstrap`

## .env Variables

| Variable | Description |
|----------|-------------|
| `HOST` | Domain name or IP address (e.g., `radio.example.com` or `1.2.3.4`) |
| `SOURCE_PASSWORD` | Password for streaming sources to connect to icecast |
| `RELAY_PASSWORD` | Password for relay servers |
| `ADMIN_PASSWORD` | Icecast admin interface password |
| `TIMEZONE` | Timezone for show times (default: `Europe/London`) |
| `SATURDAY_TIME` | Saturday show time in 24h format (default: `18:00`) |
| `SUNDAY_TIME` | Sunday show time in 24h format (default: `10:00`) |
| `SCHEDULE_USER` | Username for scheduler web UI |
| `SCHEDULE_PASSWORD_HASH` | Caddy bcrypt hash of the password |

## What Bootstrap Installs

- **icecast2** - Streaming server
- **caddy** - HTTPS reverse proxy with automatic certificates
- **ffmpeg** - Audio encoding for scheduled shows
- **radio-scheduler** - Web UI for uploading and scheduling shows
- **radio-silence** - Fallback silence stream for instant switchover

## Commands

| Command | Description |
|---------|-------------|
| `./radio bootstrap` | Full install on a fresh Ubuntu instance via SSH |
| `./radio sync` | Update icecast config on existing instance |

## Architecture

```
                    ┌─────────────┐
                    │   Caddy     │ :443 (HTTPS)
                    │  (reverse   │
                    │   proxy)    │
                    └──────┬──────┘
                           │
          ┌────────────────┼────────────────┐
          │                │                │
          ▼                ▼                ▼
    /schedule        /stream           /silence
          │                │                │
          ▼                ▼                ▼
  ┌───────────────┐ ┌───────────┐  ┌───────────────┐
  │ radio-scheduler│ │  icecast  │  │ radio-silence │
  │   (Go web UI)  │ │  :8000    │  │   (ffmpeg)    │
  └───────────────┘ └───────────┘  └───────────────┘
                           │
                    ┌──────┴──────┐
                    │  Scheduled  │
                    │   shows     │
                    │  (ffmpeg)   │
                    └─────────────┘
```

## Scheduler Web UI

Access at `https://yourdomain.com/schedule` (password protected).

- Upload audio files (MP3, OGG, FLAC, WAV up to 500MB)
- Schedule for Saturday evening or Sunday morning slots
- Test slots for arbitrary times
- Preview/download scheduled shows

## AWS Lightsail (Alternative)

- Modify the profile, region, instance name and static IP name in `./radio`
- Run `./radio create` to create/update the instance
- Run `./radio delete` to delete (keeps static IP)
- Run `./radio recreate` to delete and recreate
