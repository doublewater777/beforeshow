# Use Tencent Cloud for the V2.1 backend

BeforeShow V2.1 will use a lightweight Tencent Cloud backend for AI generation requests instead of Cloudflare Workers. The app is intended for China-accessible distribution, so the backend should stay on a domestic cloud path, receive only user-triggered generation requests, avoid long-term user data storage, and keep ticketing screenshot OCR on-device.
