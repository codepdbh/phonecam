# PhoneCam Networking & Transport Guide

PhoneCam operates 100% locally on your local area network (LAN) or over physical USB cable (via USB Tethering / USB Ethernet). No cloud servers, external STUN/TURN servers, or internet connectivity is required.

---

## 1. LAN Peer Discovery (UDP Broadcast)

- **Port**: `41235` (UDP)
- **Protocol**: Broadcast JSON beacons periodically every `1500 ms`.
- **Packet Structure**:
  ```json
  {
    "magic": "PHONECAM_DISCOVERY_V1",
    "type": "announce",
    "device": {
      "id": "phonecam_192_168_1_45",
      "name": "Samsung Galaxy S24",
      "model": "SM-S928B",
      "platform": "android",
      "ipAddress": "192.168.1.45",
      "port": 41236,
      "transportType": "wifi"
    }
  }
  ```
- **Fallback**: If UDP broadcast is blocked by your Wi-Fi router (e.g. client isolation), users can enter the phone's IP directly using the **Manual IP Connect** button in the Windows application.

---

## 2. USB Connection Strategy (USB Tethering)

To support low-latency physical USB connections without requiring Android Developer Options or USB Debugging:
1. Connect Android phone to Windows PC via USB cable.
2. Enable **USB Tethering** in Android Settings (*Settings > Network & Internet > Hotspot & Tethering > USB Tethering*).
3. Windows automatically detects a new high-speed virtual Ethernet network interface (`RNDIS` or `NCM`).
4. `NetworkInterfaceAnalyzer` detects the USB tethering subnet (`192.168.42.x` / `192.168.44.x` / `172.20.10.x` or adapter name containing `rndis`/`ncm`/`usb`) and automatically marks the transport badge as **USB**.

---

## 3. WebRTC Local Signaling

- **Host**: Android device hosts an embedded HTTP + WebSocket server on port `41236`.
- **Endpoints**:
  - `GET /ping`: Healthcheck endpoint.
  - `WS /ws`: WebSocket signaling endpoint for exchanging SDP Offer/Answer and ICE candidates.
- **ICE Configuration**: Configured with empty `iceServers` list for strictly local LAN direct candidate pairing (host candidates).
