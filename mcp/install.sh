#!/bin/bash

# Asegurar que estamos en el directorio del proyecto
cd "$(dirname "$0")"

echo "--- Instalando NothingClaw Bridge ---"

# 1. Crear entorno virtual si no existe
python3 -m venv venv
source venv/bin/activate

# 2. Instalar dependencias
pip install -r requirements.txt

# 3. Crear el servicio de systemd para que inicie solo
SERVICE_PATH="$HOME/.config/systemd/user/nothingclaw.service"
mkdir -p "$(dirname "$SERVICE_PATH")"

echo "Creando servicio de systemd..."
cat <<EOF > "$SERVICE_PATH"
[Unit]
Description=NothingClaw MCP Server
After=network.target

[Service]
ExecStart=$(pwd)/venv/bin/python $(pwd)/server.py
Restart=always

[Install]
WantedBy=default.target
EOF

# 4. Habilitar y arrancar
systemctl --user daemon-reload
systemctl --user enable --now nothingclaw.service

echo "--- Instalación completa ---"
echo "El servicio está corriendo en http://127.0.0.1:8000"
echo "Ahora solo pega esa URL en NothingLess (Settings > AI > Agents)"
