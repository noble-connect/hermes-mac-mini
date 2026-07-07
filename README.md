# Hermes Mac Mini Installer

Paquete reusable para migrar un Hermes Agent ya instalado en macOS desde `LaunchAgent` de usuario a `LaunchDaemon` del sistema, de forma que el gateway pueda arrancar después de un reboot sin login gráfico.

> Diseñado para Mac mini con macOS arm64 y Hermes Agent ya operativo.

---

## Objetivo

Convertir esta configuración:

```text
~/Library/LaunchAgents/ai.hermes.gateway.plist
```

que depende del login del usuario, en esta configuración:

```text
/Library/LaunchDaemons/ai.hermes.gateway.<user>.plist
```

que corre en dominio `system` como el usuario Hermes especificado.

---

## Qué hace el instalador

`install-hermes-daemon-macos.sh`:

1. Verifica usuario, rutas y prerequisites.
2. Valida que Hermes existe.
3. Crea backup si ya existe un LaunchDaemon anterior.
4. Genera `/Library/LaunchDaemons/<label>.plist`.
5. Lo deja con `root:wheel` y permisos `644`.
6. Desactiva/mueve el LaunchAgent viejo a backup, si existe.
7. Carga y arranca el LaunchDaemon.
8. Verifica proceso, launchctl y logs.
9. Si falla, intenta rollback al LaunchAgent anterior.

---

## Archivos

```text
hermes-mac-mini/
├── README.md
├── install-hermes-daemon-macos.sh
├── verify-hermes-daemon.sh
├── rollback-to-launchagent.sh
├── templates/
│   └── ai.hermes.gateway.plist.template
└── examples/
    └── user.env.example
```

---

## Uso rápido — one-liner desde cualquier Mac

Desde cualquier terminal Mac, un solo comando:

```bash
curl -fsSL https://raw.githubusercontent.com/noble-connect/hermes-mac-mini/main/bootstrap.sh | bash -s -- --user user --label ai.hermes.gateway.user
```

El `bootstrap.sh`:

1. Verifica macOS + `git` presente.
2. Clona (o actualiza) el repo en `~/.hermes-mac-mini/`.
3. Ejecuta `install-hermes-daemon-macos.sh` con los mismos argumentos.

## Uso alternativo — clone manual

Si preferís no usar `curl | bash`:

```bash
git clone https://github.com/noble-connect/hermes-mac-mini.git
cd hermes-mac-mini
bash install-hermes-daemon-macos.sh --user user --label ai.hermes.gateway.user
```

## Verificar

```bash
bash ~/.hermes-mac-mini/verify-hermes-daemon.sh --user user --label ai.hermes.gateway.user
```

## Rollback si algo falla

```bash
bash ~/.hermes-mac-mini/rollback-to-launchagent.sh --user user --label ai.hermes.gateway.user
```

---

## Requisitos

- macOS.
- Hermes ya instalado para el usuario target, por ejemplo:

```text
/Users/user/.hermes
/Users/user/.hermes/hermes-agent/venv/bin/python
```

- Gateway ya configurado y funcionando al menos una vez como LaunchAgent o manualmente.
- Acceso `sudo` en Terminal interactiva.
- Si el objetivo es arrancar sin login gráfico, idealmente `FileVault` debe estar `Off` o debe entenderse que el disco debe desbloquearse primero.

Verificar FileVault:

```bash
fdesetup status
```

---

## Ejemplo

```bash
bash install-hermes-daemon-macos.sh \
  --user user \
  --label ai.hermes.gateway.user
```

El LaunchDaemon resultante:

```text
/Library/LaunchDaemons/ai.hermes.gateway.user.plist
```

Ejecuta:

```text
/Users/user/.hermes/hermes-agent/venv/bin/python -m hermes_cli.main gateway run --replace
```

como usuario:

```text
user
```

---

## Seguridad

El paquete **no copia ni imprime secretos**. No debe empaquetar directamente:

```text
~/.hermes/.env
~/.hermes/auth.json
bot tokens
OAuth tokens
API keys
```

Este paquete asume que cada Mac ya tiene su Hermes configurado con sus propias credenciales.

---

## Verificación final post-reboot

Después de instalar:

```bash
sudo shutdown -r now
```

Luego:

1. No iniciar sesión gráfica.
2. Esperar 2–3 minutos.
3. Escribir al bot de Telegram de ese Hermes.
4. Si responde, el LaunchDaemon quedó validado.

---

## Notas operativas

- Si Hermes se actualiza y cambia la ruta del venv, re-ejecutar el instalador o editar el plist.
- El script separa logs daemon en:

```text
~/.hermes/logs/gateway.daemon.log
~/.hermes/logs/gateway.daemon.error.log
```

- El LaunchAgent viejo no se borra; se mueve a:

```text
~/Library/LaunchAgents.disabled/
```
