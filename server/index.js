const express = require('express');
const WebSocket = require('ws');

const app = express();
app.use(express.json());
const port = 6214;

const connections = {};

function isValidWebSocketURL(url) {
    return url.startsWith("wss://");
}

function generateUUID() {
    return Math.random().toString(36).substring(2, 10);
} // TODO: remove this and use uuid npm package

function handleWebSocketConnection(UUID, socket) {
    socket.on('message', (message) => {
    	console.log(message, message.toString())
    	if (message.toString() == "Yes, I am here!") {
        	console.log("Recieved Socket Status")
        	return
        }
        if (connections[UUID]) {
            const messageString = message.toString();
        	console.log("Message saved.")
            connections[UUID].messages.push({
                id: generateUUID(),
                message: messageString,
                step: connections[UUID].messages.length + 1
            });
        }
    });
    socket.on('error', (error) => {
        console.error(`WebSocket error for UUID: ${UUID}`, error);
        if (connections[UUID]) {
            if (!connections[UUID].errors) connections[UUID].errors = [];
            connections[UUID].errors.push({
                id: generateUUID(),
                message: error,
                step: connections[UUID].errors.length + 1
            });
        } else {
            // Optionally log or handle errors for sockets not in connections
            console.error(`Error for unregistered UUID: ${UUID}`, error);
        }
    });
}


app.post('/connect', async (req, res) => {
    const { Socket } = req.body;
    if (!Socket) {
        return res.status(400).json({ success: false, error: "No WebSocket URL provided!" });
    }
    if (!isValidWebSocketURL(Socket)) {
        return res.status(400).json({ success: false, error: "Invalid WebSocket URL" });
    }

    const UUID = generateUUID();
    let socket = new WebSocket(Socket);
    function loop(stoppedRef, socket) {
        if (!stoppedRef.stopped) {
            socket.send("Hey! Are you still there?");
            stoppedRef.timeout = setTimeout(() => loop(stoppedRef, socket), 30000);
        }
    }
    function reconnectSocket() {
        socket = new WebSocket(Socket);
        connections[UUID].socket = socket;
        handleWebSocketConnection(UUID, socket);
        socket.on('open', () => {
            let stoppedRef = { stopped: false, timeout: null };
            socket.on('close', () => {
                stoppedRef.stopped = true;
                if (stoppedRef.timeout) clearTimeout(stoppedRef.timeout);
            });
            stoppedRef.timeout = setTimeout(() => loop(stoppedRef, socket), 30000);
        });
        socket.on('close', () => {
            // Try to reconnect if UUID is still registered
            if (connections[UUID]) {
                setTimeout(reconnectSocket, 1000); // Reconnect after 1 second
            }
        });
    }

    try {
        await new Promise((resolve, reject) => {
            socket.on('error', (error) => {
                console.error(`WebSocket error for UUID: ${UUID}`, error);
                reject(error);
            });
            socket.on('open', () => {
                let stoppedRef = { stopped: false, timeout: null };
                socket.on('close', () => {
                    stoppedRef.stopped = true;
                    if (stoppedRef.timeout) clearTimeout(stoppedRef.timeout);
                });
                stoppedRef.timeout = setTimeout(() => loop(stoppedRef, socket), 10000);
                resolve();
            });
            socket.on('close', () => {
                // Try to reconnect if UUID is still registered
                if (connections[UUID]) {
                    setTimeout(reconnectSocket, 1000); // Reconnect after 1 second
                }
            });
        });
    } catch (error) {
        return res.status(500).json({ success: false, error: "WebSocket connection error" });
    }

    connections[UUID] = { socket: socket, messages: [] };
    handleWebSocketConnection(UUID, socket);

    res.json({ UUID, Socket, success: true });
});


app.post('/disconnect', (req, res) => {
    const { UUID } = req.body;
    if (!UUID) {
        return res.status(400).json({ success: false, error: "No UUID provided!" });
    }
    if (!connections[UUID]) {
        return res.status(404).json({ success: false, error: "UUID not found" });
    }

    connections[UUID].socket.close();
    delete connections[UUID];
    res.json({ UUID, success: true });
});

app.post('/send', (req, res) => {
    const { UUID, Message } = req.body;
    if (!UUID || !Message) {
        return res.status(400).json({ success: false, error: "UUID or Message not provided!" });
    }
    if (!connections[UUID] || connections[UUID].socket.readyState !== WebSocket.OPEN) {
        return res.status(404).json({ success: false, error: "Invalid UUID or WebSocket connection closed" });
    }
	console.log("Recieved", Message)
    connections[UUID].socket.send(Message);
    res.json(true);
});

app.post('/get', (req, res) => {
    const { UUID } = req.body;
    if (!UUID) {
        return res.status(400).json({ success: false, error: "No UUID provided!" });
    }
    if (!connections[UUID]) {
        return res.status(404).json({ success: false, error: "Invalid UUID" });
    }

    res.json(connections[UUID].messages);
});
app.post('/errors', (req, res) => {
    const { UUID } = req.body;
    if (!UUID) {
        return res.status(400).json({ success: false, error: "No UUID provided!" });
    }
    if (!connections[UUID]) {
        return res.status(404).json({ success: false, error: "Invalid UUID" });
    }

    res.json(connections[UUID].errors);
});

app.listen(port, () => {
    console.log(`Server running on port ${port}`);
});
