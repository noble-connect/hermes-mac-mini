# OPERADOR — Instalación Hermes Gateway como LaunchDaemon

Use este archivo cuando esté frente a una nueva Mac mini.

---

## Modo recomendado

1. Instale/configure Hermes normalmente hasta que el gateway responda por Telegram.
2. Copie esta carpeta `Hermes-MacMini-Installer` a la Mac.
3. Ejecute el instalador.
4. Verifique.
5. Reinicie y pruebe sin login gráfico.

---

## Paso 0 — Diagnóstico rápido

```bash
printf 'USER=%s\nHOME=%s\nHOST=%s\n' "$USER" "$HOME" "$(hostname)"; sw_vers; uname -m; command -v hermes || true; hermes --version || true; test -d "$HOME/.hermes" && echo "HERMES_HOME_EXISTS=yes" || echo "HERMES_HOME_EXISTS=no"; fdesetup status
```

---

## Paso 1 — Crear daemon sin cutover, opcional

Útil si quiere validar el plist antes de apagar el LaunchAgent:

```bash
bash install-hermes-daemon-macos.sh --user user --label ai.hermes.gateway.user --skip-cutover
```

---

## Paso 2 — Instalar y hacer cutover

```bash
bash install-hermes-daemon-macos.sh --user user --label ai.hermes.gateway.user
```

El script pedirá `sudo` en Terminal interactiva.

---

## Paso 3 — Verificar

```bash
bash verify-hermes-daemon.sh --user user --label ai.hermes.gateway.user
```

Busque:

```text
state = running
username = user
pid = ...
Gateway Service: running
```

---

## Paso 4 — Reinicio final

```bash
sudo shutdown -r now
```

Después:

1. No iniciar sesión gráfica.
2. Esperar 2–3 minutos.
3. Probar Telegram.
4. Si responde, instalación completa.

---

## Rollback

Si algo falla:

```bash
bash rollback-to-launchagent.sh --user user --label ai.hermes.gateway.user
```

---

## Prompt para Hermes local de la Mac nueva

Si quiere que el Hermes local reporte al orquestador:

```text
Eres el Hermes local de esta Mac mini. No modifiques archivos. Diagnostica instalación Hermes, gateway, launchd, FileVault y Tailscale. No imprimas secretos. Entrega un bloque === REPORTE PARA ORQUESTADOR === con estado actual, paths, servicios, bloqueadores y próximo paso recomendado.
```
