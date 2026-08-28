# PhoneCam Communication Protocol Specification

Version: **1.0.0**

All messages exchanged between Windows and Android over WebRTC DataChannel (or local signaling) follow a versioned JSON envelope.

---

## 1. Message Envelope

```json
{
  "protocolVersion": 1,
  "messageType": "camera.zoom",
  "requestId": "1787930000000_123",
  "timestamp": 1787930000000,
  "payload": {}
}
```

### Fields:
- `protocolVersion` (*int*): Protocol version (currently `1`).
- `messageType` (*string*): Unique command or event identifier.
- `requestId` (*string*): Client-generated unique correlation ID for requests.
- `timestamp` (*int*): Milliseconds since Unix epoch.
- `payload` (*object*): Command parameters or response data.

---

## 2. Remote Camera Commands

### `camera.switch`
Switches to the next physical camera (e.g. Front -> Main Back -> Ultra-Wide).
```json
{
  "protocolVersion": 1,
  "messageType": "camera.switch",
  "requestId": "req_01",
  "timestamp": 1787930000000,
  "payload": {}
}
```

### `camera.select`
Selects a specific camera ID.
```json
{
  "protocolVersion": 1,
  "messageType": "camera.select",
  "requestId": "req_02",
  "timestamp": 1787930000000,
  "payload": {
    "cameraId": "backMain"
  }
}
```

### `camera.zoom`
Sets the camera digital / optical zoom factor.
```json
{
  "protocolVersion": 1,
  "messageType": "camera.zoom",
  "requestId": "req_03",
  "timestamp": 1787930000000,
  "payload": {
    "zoom": 2.5
  }
}
```

### `camera.flash`
Controls camera torch/flashlight.
```json
{
  "protocolVersion": 1,
  "messageType": "camera.flash",
  "requestId": "req_04",
  "timestamp": 1787930000000,
  "payload": {
    "torch": true
  }
}
```

---

## 3. Stream Configuration Commands

### `stream.resolution`
Changes active capture resolution.
```json
{
  "protocolVersion": 1,
  "messageType": "stream.resolution",
  "requestId": "req_05",
  "timestamp": 1787930000000,
  "payload": {
    "width": 1920,
    "height": 1080,
    "label": "1080p Full HD"
  }
}
```

### `stream.fps`
Sets target streaming framerate.
```json
{
  "protocolVersion": 1,
  "messageType": "stream.fps",
  "requestId": "req_06",
  "timestamp": 1787930000000,
  "payload": {
    "fps": 60
  }
}
```

---

## 4. Capabilities & Telemetry Messages

### `device.getCapabilities`
Sent by Windows upon DataChannel opening to query hardware capabilities.
```json
{
  "protocolVersion": 1,
  "messageType": "device.getCapabilities",
  "requestId": "req_07",
  "timestamp": 1787930000000,
  "payload": {}
}
```

### `device.capabilities`
Response from Android describing available cameras, zoom limits, torch support, and resolution presets.
```json
{
  "protocolVersion": 1,
  "messageType": "device.capabilities",
  "requestId": "req_07",
  "timestamp": 1787930000000,
  "payload": {
    "deviceName": "Samsung Galaxy S24 Ultra",
    "platform": "Android",
    "cameras": [
      {
        "id": "0",
        "name": "Main Camera (1x)",
        "facing": "backMain",
        "zoomMin": 1.0,
        "zoomMax": 10.0,
        "currentZoom": 1.0,
        "hasTorch": true
      },
      {
        "id": "1",
        "name": "Front Camera",
        "facing": "front",
        "zoomMin": 1.0,
        "zoomMax": 3.0,
        "currentZoom": 1.0,
        "hasTorch": false
      }
    ],
    "supportedCodecs": ["h264", "vp8"],
    "maxResolution": { "width": 3840, "height": 2160, "label": "4K Ultra HD" },
    "maxFps": 60
  }
}
```

### `connection.stats`
Real-time telemetry sent periodically by sender or receiver.
```json
{
  "protocolVersion": 1,
  "messageType": "connection.stats",
  "requestId": "stat_01",
  "timestamp": 1787930000000,
  "payload": {
    "width": 1920,
    "height": 1080,
    "fps": 30.0,
    "bitrateKbps": 6500.0,
    "latencyMs": 24,
    "lostFrames": 0,
    "codec": "h264",
    "transportType": "wifi"
  }
}
```

---

## 5. Protocol Responses

```json
{
  "protocolVersion": 1,
  "messageType": "response.success",
  "requestId": "req_03",
  "timestamp": 1787930000050,
  "payload": {
    "status": "success",
    "data": { "zoom": 2.5 }
  }
}
```
