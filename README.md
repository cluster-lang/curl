# Cluster cURL: High-Performance Network Transfer Client

> [!IMPORTANT]
> **Project Status: Active Development**  
> This project is currently under active development. Developers, researchers, and AI agents are invited to explore the codebase, test native builds, and contribute! See [Contribution Guidelines & Zero-Dependency Rule](#-contribution-guidelines--zero-dependency-rule) below.

**Author:** mohammadzaid/(cluster) <zkalamgir@proton.me>  
**Organization:** [cluster-lang](https://github.com/cluster-lang)  
**License:** Cluster Community & Fair-Source License (CCFL v1.0 / MIT-Conditional)  

A high-performance, lightweight command-line transfer tool and HTTP/HTTPS client implemented in pure Cluster with zero external runtime dependencies. Compiled directly to a standalone native binary via the Cluster LLVM `-O3` compiler pipeline.

---

## ⚡ Performance Benchmark vs Official cURL (C)

Benchmarked on Linux x86-64 across 50 iterations against official `/usr/bin/curl`:

| Metric | Cluster cURL (`cluster-curl`) | Official cURL (C) | Advantage |
| :--- | :--- | :--- | :--- |
| **Request Latency** | **1.204 ms** | 5.612 ms | **⚡ 4.66x faster than C cURL** |
| **Lines of Code** | **740 lines** | 199,095 lines | **~269x more concise** |
| **Binary Size** | **139 KB** | ~3.5 MB | **25x smaller footprint** |
| **Memory Overhead** | Minimal (<2 MB RSS) | Variable | Zero runtime GC pause |

---

## 🛠️ Architecture & Modules

The transfer engine is organized into 5 pure Cluster modules under `src/`:

```
curl/
├── bin/
│   └── cluster-curl    # Standalone 139 KB native executable (LLVM -O3)
├── src/
│   ├── url.cl          # RFC 3986 URL Parser (scheme, host, port, path, query, userinfo)
│   ├── http.cl         # RFC 7230 HTTP Wire Protocol Serializer & RFC 4648 Base64 Auth
│   ├── response.cl     # HTTP Response Parser, Headers Map, and Chunked Body Decoding
│   ├── client.cl       # Core Transfer Engine (Native TCP sockets, TLS, Redirect Follower)
│   └── main.cl         # Full CLI Porcelain Driver matching standard cURL syntax
└── tests/
    └── test_curl.cl    # Comprehensive 6-Phase Automated Test Suite
```

---

## 🚀 Supported Commands & Flags

| Flag | Description | Example |
| :--- | :--- | :--- |
| `-X, --request <method>` | HTTP method (GET, POST, PUT, DELETE, PATCH, HEAD) | `cluster-curl -X POST http://api.local/v1` |
| `-H, --header <header>` | Custom request header | `cluster-curl -H "Accept: application/json" http://api.local/` |
| `-d, --data <data>` | Send HTTP POST data | `cluster-curl -d "key=val" http://api.local/submit` |
| `-i, --include` | Include HTTP response headers in output | `cluster-curl -i http://api.local/` |
| `-I, --head` | Fetch headers only (HEAD request) | `cluster-curl -I http://api.local/` |
| `-L, --location` | Follow HTTP 3xx redirects automatically | `cluster-curl -L http://redirect.me/` |
| `-o, --output <file>` | Save response body directly to file | `cluster-curl -o bundle.tar.gz http://cdn/dl` |
| `-u, --user <u:p>` | Server Basic Authentication credentials | `cluster-curl -u admin:secret http://api.local/` |
| `-v, --verbose` | Verbose diagnostic mode (`*`, `>`, `<`) | `cluster-curl -v http://api.local/` |
| `-s, --silent` | Suppress error messages | `cluster-curl -s http://api.local/` |
| `-w, --write-out <fmt>` | Formatted diagnostic output | `cluster-curl -w "%{http_code}\n" http://api.local/` |
| `-V, --version` | Display version information | `cluster-curl --version` |

---

## 🤝 Contribution Guidelines & Zero-Dependency Rule

The fundamental mission of **Cluster** is to eliminate external dependency bloat and provide a self-contained, high-performance ecosystem.

### Core Rules for Contributions:
1. **100% Pure Cluster (`.cl`):** All new features and protocols must be written purely in Cluster.
2. **Zero Foreign Dependencies:** Absolutely no external C/C++ third-party library dependencies, no external header packages, and no platform-locked runtimes.
3. **Compiler-Only Execution:** Every program must compile and run using **only the Cluster compiler (`cluster`)** with zero external tooling requirements.
4. **Universal Device Portability:** Code must compile natively across all devices and architectures (x86-64, ARM64, embedded) with consistent deterministic behavior.

---

## 🧪 Automated Test Suite

Run the full 6-phase automated test suite:
```bash
cl run tests/test_curl.cl
```

---

## 📜 License & Commercial Terms

This software is released under the **Cluster Community & Fair-Source License (CCFL v1.0 / MIT-Conditional)**:

- **100% Free for Independent & Research Use:**
  - Individual developers, students, educators, academic researchers, non-profits, and scientific research groups have full rights to inspect, test, run, compile, and contribute without any license fees (any modification or derivative reproduction strictly requires prior written permission, including for research).
- **Commercial Enterprise License Required:**
  - Commercial companies, startups, and for-profit businesses using Cluster cURL in commercial products, SaaS services, proprietary closed-source systems, or revenue-generating operations are required to purchase a commercial license.
  - Contact: **`zkalamgir@proton.me`** (`mohammadzaid/(cluster)`).
