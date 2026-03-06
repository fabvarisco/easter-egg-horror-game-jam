const WebSocket = require('ws');

const PORT = process.env.PORT || 8080;
const wss = new WebSocket.Server({ port: PORT });

// Room structure: { roomCode: { host: ws, peers: Map<peerId, ws>, nextPeerId: 2 } }
const rooms = new Map();

console.log(`Relay server running on port ${PORT}`);

wss.on('connection', (ws) => {
    let currentRoom = null;
    let peerId = null;

    ws.on('message', (data) => {
        try {
            const msg = JSON.parse(data.toString());
            handleMessage(ws, msg);
        } catch (e) {
            console.error('Invalid message:', e);
        }
    });

    ws.on('close', () => {
        if (currentRoom && rooms.has(currentRoom)) {
            const room = rooms.get(currentRoom);

            if (room.host === ws) {
                // Host left, close room
                room.peers.forEach((peerWs) => {
                    send(peerWs, { type: 'error', message: 'Host disconnected' });
                    peerWs.close();
                });
                rooms.delete(currentRoom);
                console.log(`Room ${currentRoom} closed (host left)`);
            } else {
                // Peer left
                room.peers.delete(peerId);
                send(room.host, { type: 'peer_left', peer_id: peerId });
                room.peers.forEach((peerWs) => {
                    send(peerWs, { type: 'peer_left', peer_id: peerId });
                });
                console.log(`Peer ${peerId} left room ${currentRoom}`);
            }
        }
    });

    function handleMessage(ws, msg) {
        switch (msg.type) {
            case 'create':
                createRoom(ws, msg.room);
                break;
            case 'join':
                joinRoom(ws, msg.room);
                break;
            case 'leave':
                leaveRoom(ws);
                break;
            case 'game':
                relayGameData(ws, msg);
                break;
        }
    }

    function createRoom(ws, roomCode) {
        if (rooms.has(roomCode)) {
            send(ws, { type: 'error', message: 'Room already exists' });
            return;
        }

        rooms.set(roomCode, {
            host: ws,
            peers: new Map(),
            nextPeerId: 2
        });

        currentRoom = roomCode;
        peerId = 1;
        send(ws, { type: 'created', room: roomCode });
        console.log(`Room ${roomCode} created`);
    }

    function joinRoom(ws, roomCode) {
        if (!rooms.has(roomCode)) {
            send(ws, { type: 'error', message: 'Room not found' });
            return;
        }

        const room = rooms.get(roomCode);

        if (room.peers.size >= 3) { // Max 4 players (1 host + 3 peers)
            send(ws, { type: 'error', message: 'Room is full' });
            return;
        }

        peerId = room.nextPeerId++;
        room.peers.set(peerId, ws);
        currentRoom = roomCode;

        // Notify joiner
        send(ws, { type: 'joined', peer_id: peerId, room: roomCode });

        // Notify host
        send(room.host, { type: 'peer_joined', peer_id: peerId });

        // Notify other peers
        room.peers.forEach((peerWs, pId) => {
            if (pId !== peerId) {
                send(peerWs, { type: 'peer_joined', peer_id: peerId });
            }
        });

        console.log(`Peer ${peerId} joined room ${roomCode}`);
    }

    function leaveRoom(ws) {
        // Handled in close event
        ws.close();
    }

    function relayGameData(ws, msg) {
        if (!currentRoom || !rooms.has(currentRoom)) return;

        const room = rooms.get(currentRoom);
        const fromId = peerId;
        const targetId = msg.target || 0;

        const relayMsg = {
            type: 'game',
            from: fromId,
            data: msg.data
        };

        if (targetId === 0) {
            // Broadcast to all except sender
            if (room.host !== ws) {
                send(room.host, relayMsg);
            }
            room.peers.forEach((peerWs, pId) => {
                if (peerWs !== ws) {
                    send(peerWs, relayMsg);
                }
            });
        } else {
            // Send to specific peer
            if (targetId === 1) {
                send(room.host, relayMsg);
            } else if (room.peers.has(targetId)) {
                send(room.peers.get(targetId), relayMsg);
            }
        }
    }
});

function send(ws, data) {
    if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify(data));
    }
}
