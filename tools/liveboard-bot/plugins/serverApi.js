import express from 'express';
import { spawn } from 'child_process';
import fs from 'fs';
import path from 'path';
import { getPalRestSnapshot } from './palRest.js';

let serverChildProcess = null;

function isProcessRunningSilent(imageFilter = 'PalServer*') {
    return new Promise(resolve => {
        try {
            const child = spawn('tasklist', ['/FI', `IMAGENAME eq ${imageFilter}`], {
                windowsHide: true,
                stdio: ['ignore', 'pipe', 'ignore']
            });
            let out = '';
            child.stdout?.on('data', chunk => { out += chunk; });
            child.on('close', () => resolve(out.includes('PalServer')));
            child.on('error', () => resolve(false));
        } catch {
            resolve(false);
        }
    });
}

function killProcessSilent(imageName) {
    return new Promise(resolve => {
        try {
            const child = spawn('taskkill', ['/IM', imageName, '/F', '/T'], {
                windowsHide: true,
                stdio: 'ignore'
            });
            child.on('close', () => resolve());
            child.on('error', () => resolve());
        } catch {
            resolve();
        }
    });
}

export function initServerApi(options = {}) {
    const port = options.port || process.env.HTTP_PORT || 3001;
    const adminKey = options.adminKey || process.env.REMOTE_ADMIN_KEY || 'DefaultSecretKey';
    const palExe = options.palExe || process.env.PAL_SERVER_EXE || 'C:\\PalworldServer\\PalServer.exe';
    const palArgs = (options.palArgs || process.env.PAL_SERVER_ARGS || '-port=8211').match(/(?:[^\s"]+|"[^"]*")+/g) || [];
    const statePath = options.statePath || process.env.LIVEBOARD_STATE_PATH || 'Pal/Saved/liveboard_state.json';
    let cachedState = { ServerOnline: false, PlayerCount: 0, Players: [], ActiveBosses: [] };
    let cachedStateMtime = -1;

    const readState = async () => {
        try {
            const stat = await fs.promises.stat(statePath);
            if (stat.mtimeMs !== cachedStateMtime) {
                cachedState = JSON.parse(await fs.promises.readFile(statePath, 'utf-8'));
                cachedStateMtime = stat.mtimeMs;
            }
        } catch { }
        return cachedState;
    };

    const app = express();
    app.use(express.json());

    const authGuard = (req, res, next) => {
        const header = req.headers.authorization;
        if (!header || header !== `Bearer ${adminKey}`) {
            return res.status(401).json({ success: false, error: 'Unauthorized' });
        }
        next();
    };

    app.get('/api/server/status', async (req, res) => {
        const stateData = await readState();
        const palSnapshot = await getPalRestSnapshot();

        let isProcessRunning = serverChildProcess !== null && !serverChildProcess.killed;
        if (!isProcessRunning) {
            isProcessRunning = await isProcessRunningSilent('PalServer-Win64-Shipping.exe');
        }

        // The JSON file can remain stale after a graceful server shutdown.
        // REST reachability or the local PalServer process determines liveness.
        const isOnline = Boolean(palSnapshot.reachable || isProcessRunning);
        const restPlayers = palSnapshot.reachable ? palSnapshot.players : null;

        return res.json({
            success: true,
            isProcessRunning,
            serverOnline: isOnline,
            playerCount: restPlayers ? restPlayers.length : (stateData.PlayerCount ?? (stateData.Players ? stateData.Players.length : 0)),
            maxPlayers: stateData.MaxPlayers || 32,
            timestamp: Date.now()
        });
    });

    app.post('/api/server/start', authGuard, async (req, res) => {
        let isAlreadyRunning = serverChildProcess !== null && !serverChildProcess.killed;
        if (!isAlreadyRunning) {
            isAlreadyRunning = await isProcessRunningSilent('PalServer-Win64-Shipping.exe');
        }

        if (isAlreadyRunning) {
            return res.status(400).json({ success: false, message: 'Server is already running.' });
        }

        if (!fs.existsSync(palExe)) {
            return res.status(500).json({ success: false, message: `Executable not found at: ${palExe}` });
        }

        let workingDir = path.dirname(palExe);
        if (workingDir.replace(/\\/g, '/').toLowerCase().endsWith('/pal/binaries/win64')) {
            workingDir = path.resolve(workingDir, '../../..');
        }

        serverChildProcess = spawn(palExe, palArgs, {
            cwd: workingDir,
            detached: true,
            stdio: 'ignore',
            windowsHide: true
        });

        serverChildProcess.on('exit', (code) => {
            console.log(`[Server API] Process exited with code ${code}`);
            serverChildProcess = null;
        });

        serverChildProcess.unref();
        console.log(`[Server API] Spawned PalServer from ${workingDir} (PID: ${serverChildProcess.pid})`);

        return res.json({ success: true, message: 'Server started.', pid: serverChildProcess.pid });
    });

    app.post('/api/server/stop', authGuard, async (req, res) => {
        if (serverChildProcess && !serverChildProcess.killed) {
            serverChildProcess.kill();
            serverChildProcess = null;
        }

        await killProcessSilent('PalServer-Win64-Shipping.exe');
        await killProcessSilent('PalServer.exe');

        try {
            if (fs.existsSync(statePath)) {
                const raw = JSON.parse(fs.readFileSync(statePath, 'utf-8'));
                raw.ServerOnline = false;
                raw.PlayerCount = 0;
                fs.writeFileSync(statePath, JSON.stringify(raw, null, 2));
            }
        } catch { }

        return res.json({ success: true, message: 'Server terminated.' });
    });

    const server = app.listen(port, () => {
        console.log(`[Server API] Remote Controller listening on port ${port}`);
    });

    return { app, server };
}
