# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an IoT monitoring system for gas stations that manages indoor and outdoor alarm devices via MQTT. The system consists of:

- **Backend**: Flask REST API with MQTT message forwarding service
- **Frontend**: Vue 3 + Element Plus web management interface
- **WeChat Mini Program**: Mobile device binding and monitoring interface
- **Embedded Firmware**: Lua scripts for AIR-8000 (indoor) and AIR780EPM (outdoor) devices
- **Data Forwarding Script**: Standalone Python MQTT relay script

### Core Functionality

The system enables bidirectional communication between indoor and outdoor devices at gas stations:
- Indoor devices (AIR-8000) detect liquid level alarms and forward to outdoor devices
- Outdoor devices (AIR780EPM) report battery status to indoor devices
- Backend automatically forwards messages between devices at the same station
- Web interface manages stations, devices, users, and monitors alarms
- WeChat mini program allows mobile device binding and monitoring

## Development Commands

### Backend (Flask)

```bash
# Navigate to backend directory
cd backend

# Install dependencies
pip install -r requirements.txt

# Run development server (includes MQTT service)
python app.py

# Run with specific environment
FLASK_ENV=development python app.py
FLASK_ENV=production python app.py

# Default server runs on http://0.0.0.0:5000
```

### Frontend (Vue 3 + Vite)

```bash
# Navigate to frontend directory
cd frontend

# Install dependencies
npm install

# Run development server with hot reload
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview

# Development server runs on http://localhost:5173
# API requests proxy to http://localhost:5000
```

### WeChat Mini Program

```bash
# Navigate to WeChat binding system
cd WxBindingSystem

# Install dependencies
npm install

# Open in WeChat DevTools
# Import project directory: WxBindingSystem/
# AppID configured in project.config.json
```

### Data Forwarding Script

```bash
# Run standalone MQTT relay (alternative to backend MQTT service)
python Data_Forwarding.py

# Prompts for indoor and outdoor device IMEIs
# Creates bidirectional message forwarding between devices
```

## Architecture

### Backend Structure

```
backend/
├── app.py              # Application entry point, starts Flask + MQTT
├── config.py           # Configuration (DB, MQTT, JWT settings)
├── requirements.txt    # Python dependencies
└── app/
    ├── __init__.py     # Flask app factory, blueprint registration
    ├── models.py       # SQLAlchemy models (User, Station, Device, AlarmLog, CommLog)
    ├── api/            # REST API endpoints
    │   ├── auth.py     # Login, token management
    │   ├── users.py    # User CRUD
    │   ├── stations.py # Station CRUD, device binding
    │   ├── devices.py  # Device CRUD, status queries
    │   ├── alarms.py   # Alarm log queries
    │   └── comm_logs.py # Communication log queries
    └── services/
        └── mqtt_service.py # MQTT client, message forwarding logic
```

### Frontend Structure

```
frontend/src/
├── main.js             # Vue app initialization
├── App.vue             # Root component
├── router/
│   └── index.js        # Vue Router configuration, auth guards
├── store/              # Pinia state management
├── api/                # Axios API client modules
├── components/         # Reusable Vue components
└── views/              # Page components
    ├── Login.vue       # Login page
    ├── Layout.vue      # Main layout with navigation
    ├── Dashboard.vue   # Overview statistics
    ├── Users.vue       # User management (admin only)
    ├── Stations.vue    # Station management
    ├── Devices.vue     # Device management
    ├── Monitor.vue     # Real-time device monitoring
    ├── Alarms.vue      # Alarm log history
    └── CommLogs.vue    # Communication log history
```

### WeChat Mini Program Structure

```
WxBindingSystem/miniprogram/
├── app.ts              # Mini program entry, global state
├── app.json            # Page routing, window config
├── pages/              # Mini program pages
│   ├── index/          # Home page with device list
│   ├── login/          # Login page
│   ├── stations/       # Station selection
│   ├── devices/        # Device binding management
│   ├── logs/           # Alarm and communication logs
│   └── profile/        # User profile
├── components/         # Reusable components
└── utils/              # Utility functions (API, auth)
```

### Database Models

**User**: Authentication, role-based access (admin/user), station associations

**Station**: Gas station information, device grouping

**Device**: Indoor/outdoor devices with IMEI, station binding, online status, battery voltage

**AlarmLog**: Records alarm events from indoor devices and forwarding status

**CommLog**: Tracks all MQTT messages (receive/forward) for debugging

### MQTT Message Flow

1. **Indoor Device Publishes**: `/AIR8000/PUB/{imei}` → Backend subscribes
2. **Backend Processes**: Validates device, checks station binding, logs message
3. **Backend Forwards**: Publishes to `/780EHV/SUB/{outdoor_imei}` for each outdoor device at same station
4. **Outdoor Device Publishes**: `/780EHV/PUB/{imei}` → Backend subscribes
5. **Backend Forwards**: Publishes to `/AIR8000/SUB/{indoor_imei}` for indoor device at same station

Message forwarding only occurs between devices bound to the same station. Devices without station binding receive messages but do not forward.

### Key Configuration

**Backend** (`backend/config.py`):
- MySQL database connection (host, port, credentials)
- MQTT broker connection (host, port, credentials)
- MQTT topic prefixes for indoor/outdoor devices
- JWT token expiration and secret keys
- Device offline threshold (13 hours)

**Frontend** (`frontend/vite.config.js`):
- API proxy to backend (`/api` → `http://localhost:5000`)
- Build output directory and asset configuration

**WeChat Mini Program** (`WxBindingSystem/project.config.json`):
- AppID and project settings
- API base URL configuration in `utils/` files

### Authentication

- Backend uses Flask-JWT-Extended for token-based auth
- Frontend stores JWT in localStorage, includes in Authorization header
- Router guards check token presence and admin role
- Default admin account: `admin` / `admin123` (configurable in `config.py`)

### Device Auto-Registration

When a device publishes an MQTT message:
1. Backend checks if device exists in database
2. If not found, automatically creates device record with IMEI and type
3. If device type mismatches (e.g., registered as indoor but publishes as outdoor), corrects type and unbinds from station
4. Updates `last_seen` timestamp on every message

### Embedded Firmware

**AIR-8000** (Indoor): Lua scripts in `AIR-8000/` directory
- `main.lua`: Main application logic
- `single_mqtt.lua`: MQTT client implementation
- `exaudio.lua`: Audio playback for alarms

**AIR780EPM** (Outdoor): Lua scripts in `AIR780EPM/` directory
- Similar structure to AIR-8000
- Includes battery monitoring and reporting

Both devices use LuatOS framework and communicate via MQTT.

## Important Notes

- Backend MQTT service runs in a daemon thread alongside Flask
- Use `use_reloader=False` in Flask to prevent duplicate MQTT connections
- Frontend uses Vite proxy in development; production requires nginx or similar
- WeChat mini program requires valid AppID and domain whitelist configuration
- MQTT broker credentials are hardcoded in `config.py` - use environment variables in production
- Database tables are auto-created on first run via `db.create_all()`
- Communication logs can grow large - consider implementing log rotation or archival
