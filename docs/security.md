# PhoneCam Pairing & Security Specification

PhoneCam incorporates a zero-trust LAN pairing mechanism to ensure unauthorized devices on the local network cannot access your phone's camera feed without explicit consent.

---

## 1. 6-Digit PIN Pairing Flow

```mermaid
sequenceDiagram
    participant PC as Windows PC
    participant Phone as Android Phone
    participant User as Phone User

    PC->>Phone: WebSocket Connect & Pairing Request
    Phone->>Phone: Generate 6-digit Secure Random PIN (e.g. 458127)
    Phone->>User: Display Pairing Modal: "DANIEL-PC wants to connect. PIN: 458127"
    Phone->>PC: Send Pairing Required Event
    PC->>PC: Display PIN entry / verification prompt
    User->>Phone: Tap "Approve Connection"
    Phone->>PC: Issue Cryptographic Auth Token
    Phone->>Phone: Store PC in Trusted Hosts store
```

---

## 2. Persistent Trusted Hosts Store

- After initial pairing approval, the phone securely stores a `TrustedHost` record:
  - `deviceId`: Unique hardware/client UUID of the PC.
  - `deviceName`: Friendly host name (e.g. `DANIEL-PC`).
  - `authToken`: Random high-entropy authorization secret.
  - `pairedAt`: Pairing timestamp.
  - `lastConnectedAt`: Timestamp of last active streaming session.
- Subsequent connections from the same PC pass the `authToken` during the initial handshake, permitting instant auto-connection without re-entering PINs.
