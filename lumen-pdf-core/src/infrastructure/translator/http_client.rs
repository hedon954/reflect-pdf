use reqwest::Client;
use std::sync::OnceLock;
use std::time::Duration;

/// Shared HTTP client used by every translator (LLM + fallback).
///
/// `reqwest::Client` keeps an internal connection pool and TLS session cache;
/// rebuilding it per request would force a fresh TCP + TLS handshake every
/// time. We also enforce explicit timeouts here so a stalled upstream LLM
/// gateway can never hang the UI indefinitely — the use case can fall back to
/// MyMemory once the timeout fires.
static HTTP_CLIENT: OnceLock<Client> = OnceLock::new();

pub fn shared_client() -> &'static Client {
    HTTP_CLIENT.get_or_init(|| {
        Client::builder()
            .connect_timeout(Duration::from_secs(3))
            // Total request timeout — caps both blocking RTT *and* slow streaming
            // responses. 30s is enough for a long word-level translation with a
            // verbose model while still bounding worst-case latency.
            .timeout(Duration::from_secs(30))
            .pool_idle_timeout(Duration::from_secs(60))
            .build()
            // `Client::builder().build()` only fails if the system TLS backend
            // is unusable; in that case fall back to default `Client::new()`
            // so the rest of the app still works (translation will fail loudly
            // with a network error rather than crashing the process).
            .unwrap_or_else(|_| Client::new())
    })
}
