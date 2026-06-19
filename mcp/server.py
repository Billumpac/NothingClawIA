#!/usr/bin/env python3
import os
import shutil
import subprocess
from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Route
import uvicorn


def asegurar_ollama():
    check_ollama = subprocess.run(["pgrep", "ollama"], capture_output=True)
    if check_ollama.returncode != 0:
        print("Ollama no estÃ¡ activo. Iniciando servicio...")
        subprocess.Popen(["ollama", "serve"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        import time
        time.sleep(3)


def detectar_gestor_paquetes():
    try:
        with open("/etc/os-release", "r") as f:
            contenido = f.read().lower()
        if "arch" in contenido or "cachyos" in contenido:
            return "sudo pacman -S --noconfirm", "pacman"
        elif "fedora" in contenido:
            return "sudo dnf install -y", "dnf"
        elif "debian" in contenido or "ubuntu" in contenido:
            return "sudo apt-get install -y", "apt"
    except Exception:
        pass
    return "sudo pacman -S --noconfirm", "pacman"


TOOLS = [
    {
        "name": "verificar_programa_instalado",
        "description": "Busca de forma universal si un programa existe en el PATH de la distro.",
        "parameters": {
            "type": "object",
            "properties": {
                "nombre_programa": {"type": "string"}
            },
            "required": ["nombre_programa"]
        }
    },
    {
        "name": "gestionar_programa",
        "description": "Ejecuta o instala de manera dinamica cualquier software.",
        "parameters": {
            "type": "object",
            "properties": {
                "accion": {"type": "string", "enum": ["ejecutar", "instalar"]},
                "nombre_programa": {"type": "string"}
            },
            "required": ["accion", "nombre_programa"]
        }
    },
    {
        "name": "controlar_escritorio_axctl",
        "description": "Envia comandos de control de ventanas y entornos al daemon axctl.",
        "parameters": {
            "type": "object",
            "properties": {
                "categoria": {"type": "string", "enum": ["window", "workspace", "config"]},
                "accion": {"type": "string"},
                "parametro": {"type": "string"}
            },
            "required": ["categoria", "accion"]
        }
    }
]


def invoke_tool(name, arguments):
    if name == "verificar_programa_instalado":
        ruta = shutil.which(arguments.get("nombre_programa", ""))
        if ruta:
            return {"content": f"El programa '{arguments['nombre_programa']}' SI esta instalado en: {ruta}", "error": None}
        return {"content": f"El programa '{arguments['nombre_programa']}' NO esta instalado en el sistema.", "error": None}

    elif name == "gestionar_programa":
        accion = arguments.get("accion", "")
        nombre = arguments.get("nombre_programa", "")
        if accion == "ejecutar":
            try:
                subprocess.Popen(
                    f"nohup {nombre} > /dev/null 2>&1 &",
                    shell=True,
                    env=os.environ,
                    preexec_fn=os.setpgrp
                )
                return {"content": f"Ejecucion enviada para '{nombre}' con exito.", "error": None}
            except Exception as e:
                return {"content": "", "error": str(e)}
        elif accion == "instalar":
            comando_base, gestor = detectar_gestor_paquetes()
            cmd = f"{comando_base} {nombre}"
            try:
                r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
                if r.returncode == 0:
                    return {"content": f"Instalacion exitosa de '{nombre}' usando {gestor}.", "error": None}
                return {"content": "", "error": f"Fallo {gestor}: {r.stderr.strip()}"}
            except Exception as e:
                return {"content": "", "error": str(e)}
        return {"content": "", "error": "Accion no valida."}

    elif name == "controlar_escritorio_axctl":
        categoria = arguments.get("categoria", "")
        accion = arguments.get("accion", "")
        parametro = arguments.get("parametro", "")
        cmd = f"/usr/local/bin/axctl {categoria} {accion}"
        if parametro:
            cmd += f" {parametro}"
        try:
            r = subprocess.run(cmd, shell=True, capture_output=True, text=True, env=os.environ)
            if r.returncode == 0:
                return {"content": r.stdout.strip() or "Success", "error": None}
            return {"content": "", "error": r.stderr.strip()}
        except Exception as e:
            return {"content": "", "error": str(e)}

    return {"content": "", "error": f"Tool '{name}' no encontrada"}


async def tools_endpoint(request):
    return JSONResponse(TOOLS)


async def invoke_endpoint(request):
    body = await request.json()
    name = body.get("name", "")
    arguments = body.get("arguments", {})
    result = invoke_tool(name, arguments)
    return JSONResponse(result)


if __name__ == "__main__":
    app = Starlette(routes=[
        Route('/tools', tools_endpoint, methods=["GET"]),
        Route('/tools', invoke_endpoint, methods=["POST"]),
    ])
    asegurar_ollama()
    print("Pasarela NothingClaw en http://127.0.0.1:8000 ...")
    uvicorn.run(app, host="127.0.0.1", port=8000)