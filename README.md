# ClerkIQ Playwright MCP

A custom MCP (Model Context Protocol) server that combines Playwright browser automation with Browserbase cloud browser infrastructure. Built for ClerkIQ's AI-powered invoice processing workflows.

## What This Does

This MCP server solves a critical problem: **running browser automation in the cloud with persistent download retrieval**.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         ClerkIQ Playwright MCP                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────────────┐     ┌──────────────────────────────────────┐ │
│  │  Browserbase Tools   │     │      Playwright Tools (Proxied)      │ │
│  │  (Custom)            │     │      from @playwright/mcp            │ │
│  ├──────────────────────┤     ├──────────────────────────────────────┤ │
│  │ • create_session     │     │ • browser_navigate                   │ │
│  │ • configure_downloads│     │ • browser_click                      │ │
│  │ • get_downloads      │     │ • browser_type                       │ │
│  │ • stop_session       │     │ • browser_snapshot                   │ │
│  └──────────────────────┘     │ • browser_take_screenshot            │ │
│           │                   │ • ... (all Playwright MCP tools)     │ │
│           │                   └──────────────────────────────────────┘ │
│           │                                     │                      │
│           ▼                                     ▼                      │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    Browserbase Cloud Browser                      │  │
│  │  • Residential proxies (bypass bot detection)                     │  │
│  │  • CAPTCHA solving                                                │  │
│  │  • Cloud-synced downloads                                         │  │
│  │  • Headless Chrome in the cloud                                   │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Why We Built This

### The Problem

ClerkIQ needs to automate invoice downloads from vendor portals (Amazon Business, Staples, etc.). These portals have:

1. **Bot detection** - Block headless browsers and datacenter IPs
2. **CAPTCHAs** - Require human verification
3. **File downloads** - PDFs that need to be retrieved after browser sessions
4. **Complex authentication** - Multi-step login flows

### The Solution

This MCP server combines:

| Component | Purpose |
|-----------|---------|
| **Browserbase** | Cloud browsers with residential proxies + CAPTCHA solving |
| **Playwright MCP** | Full browser automation capabilities |
| **Custom download tools** | Retrieve files from cloud browser sessions |

### ClerkIQ Integration Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        ClerkIQ Invoice Processing                        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. CREATE SESSION                                                        │
│    browserbase_create_session(proxies=true, solve_captchas=true)        │
│    → Returns: session_id, cdp_url                                        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 2. CONFIGURE DOWNLOADS                                                   │
│    browserbase_configure_downloads(cdp_url)                              │
│    → Enables cloud download sync via CDP protocol                        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 3. AUTOMATE BROWSER (Playwright tools)                                   │
│    browser_navigate("https://amazon.business.com")                       │
│    browser_type(ref="email", text="user@company.com")                   │
│    browser_click(ref="login-button")                                     │
│    browser_click(ref="download-invoice")  ← Triggers PDF download       │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 4. RETRIEVE DOWNLOADS                                                    │
│    browserbase_get_downloads(session_id)                                 │
│    → Returns: [{filename, content_base64, size_bytes}, ...]             │
│    → Decode base64 → Save invoice PDFs to ClerkIQ storage               │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 5. CLEANUP                                                               │
│    browserbase_stop_session(session_id)                                  │
│    → Releases cloud resources, stops billing                             │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 6. PROCESS INVOICES                                                      │
│    ClerkIQ extracts data from PDFs using AI                              │
│    → Vendor, amount, date, line items, etc.                              │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Installation

### Prerequisites

- Python 3.11+
- [UV](https://docs.astral.sh/uv/) for package management
- Browserbase account with API key and project ID
- Node.js (for Playwright MCP proxy)

### Setup

```bash
# Clone the repo
git clone https://github.com/jayozer/clerkiq-playwright-mcp.git
cd clerkiq-playwright-mcp

# Install dependencies
uv sync

# Create .env file
cat > .env << EOF
BROWSERBASE_API_KEY=your_api_key_here
BROWSERBASE_PROJECT_ID=your_project_id_here
EOF
```

### Install in Claude Code

```bash
uv run fastmcp install claude-code src/clerkiq_playwright_mcp/server.py \
  --name clerkiq-playwright \
  --with browserbase \
  --with websockets \
  --env-file .env
```

Then restart Claude Code. The tools will be available as `mcp__clerkiq-playwright__*`.

---

## Tools Reference

### Custom Browserbase Tools

#### `browserbase_create_session`

Creates a new cloud browser session with Browserbase.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `proxies` | bool | `true` | Enable residential proxies |
| `solve_captchas` | bool | `true` | Enable automatic CAPTCHA solving |
| `timeout_seconds` | int | `1800` | Session timeout (30 min default) |

**Returns:**
```json
{
  "session_id": "810a5708-94e6-4e91-8a94-d9c4dc68173e",
  "cdp_url": "wss://connect.usw2.browserbase.com/?signingKey=...",
  "live_url": "https://browserbase.com/sessions/810a5708..."
}
```

#### `browserbase_configure_downloads`

Configures the browser to sync downloads to Browserbase cloud storage. **Must be called after connecting but before any downloads.**

| Parameter | Type | Description |
|-----------|------|-------------|
| `cdp_url` | string | CDP websocket URL from create_session |

**Returns:** `{"result": true}` on success

#### `browserbase_get_downloads`

Retrieves downloaded files from a session. Polls until files are available.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `session_id` | string | required | Session ID from create_session |
| `timeout_seconds` | int | `120` | Max wait time for downloads |
| `poll_interval` | float | `5` | Seconds between polling attempts |

**Returns:**
```json
{
  "files": [
    {
      "filename": "invoice-12345.pdf",
      "content_base64": "JVBERi0xLjQK...",
      "size_bytes": 45678
    }
  ],
  "count": 1,
  "message": "Retrieved 1 file(s)"
}
```

#### `browserbase_stop_session`

Stops a session and releases cloud resources. **Always call this when done to avoid unnecessary charges.**

| Parameter | Type | Description |
|-----------|------|-------------|
| `session_id` | string | Session ID to stop |

**Returns:** `{"result": true}` on success

### Proxied Playwright Tools

All standard Playwright MCP tools are available:

| Tool | Description |
|------|-------------|
| `browser_navigate` | Navigate to a URL |
| `browser_click` | Click an element |
| `browser_type` | Type text into an input |
| `browser_snapshot` | Get accessibility tree (for finding elements) |
| `browser_take_screenshot` | Capture screenshot |
| `browser_fill_form` | Fill multiple form fields |
| `browser_select_option` | Select dropdown option |
| `browser_press_key` | Press keyboard key |
| `browser_wait_for` | Wait for text or time |
| `browser_tabs` | Manage browser tabs |
| ... | And more |

---

## Usage Examples

### Basic Session Lifecycle

```python
# In Claude Code or any MCP client

# 1. Create session
session = browserbase_create_session(proxies=True, solve_captchas=True)

# 2. Configure downloads
browserbase_configure_downloads(cdp_url=session["cdp_url"])

# 3. Navigate and interact
browser_navigate(url="https://example.com")
browser_click(ref="download-button")

# 4. Get downloaded files
downloads = browserbase_get_downloads(session_id=session["session_id"])
for file in downloads["files"]:
    content = base64.b64decode(file["content_base64"])
    # Save or process the file

# 5. Cleanup
browserbase_stop_session(session_id=session["session_id"])
```

### ClerkIQ Invoice Download Example

```
User: Download my latest invoice from Amazon Business

Claude: I'll create a Browserbase session and navigate to Amazon Business.

1. Creating session with proxies and CAPTCHA solving...
   ✓ Session created: 810a5708-94e6-4e91-8a94-d9c4dc68173e

2. Configuring downloads...
   ✓ Downloads configured

3. Navigating to Amazon Business...
   [browser_navigate to https://amazon.business.com]

4. Taking snapshot to find login form...
   [browser_snapshot]

5. Entering credentials...
   [browser_type email field]
   [browser_type password field]
   [browser_click sign-in button]

6. Navigating to orders...
   [browser_click "Your Orders"]

7. Downloading invoice...
   [browser_click "Download Invoice"]

8. Retrieving downloaded file...
   ✓ Retrieved: invoice-2024-01-15.pdf (125KB)

9. Stopping session...
   ✓ Session stopped

I've downloaded your invoice. The file is invoice-2024-01-15.pdf.
```

---

## Testing

### Run All Tests

```bash
# Unit tests only (no Browserbase API calls)
uv run pytest tests/ -v --ignore=tests/test_integration.py

# Integration tests (requires real Browserbase credentials)
uv run pytest tests/test_integration.py -v
```

### Test Coverage

| Test File | Tests | Coverage |
|-----------|-------|----------|
| `test_browserbase_tools.py` | 12 | All 4 Browserbase tools |
| `test_models.py` | 15 | Pydantic model validation |
| `test_server.py` | 2 | Server configuration |
| `test_integration.py` | 2 | End-to-end with real Browserbase |

**Total: 31 tests**

---

## Project Structure

```
clerkiq-playwright-mcp/
├── src/clerkiq_playwright_mcp/
│   ├── __init__.py
│   ├── server.py              # FastMCP server with Playwright proxy
│   ├── models.py              # Pydantic models
│   └── tools/
│       ├── __init__.py
│       └── browserbase.py     # Custom Browserbase tools
├── tests/
│   ├── conftest.py            # Test fixtures
│   ├── test_browserbase_tools.py
│   ├── test_models.py
│   ├── test_server.py
│   └── test_integration.py
├── .env                       # API keys (gitignored)
├── pyproject.toml
└── README.md
```

---

## Architecture

### How the MCP Server Works

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            Claude Code                                   │
│                                                                          │
│  User: "Download invoice from Amazon Business"                          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ MCP Protocol (stdio)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     ClerkIQ Playwright MCP Server                        │
│                         (FastMCP + Python)                               │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                     Tool Router                                  │    │
│  │                                                                  │    │
│  │   browserbase_*  ──────►  Custom Python Functions               │    │
│  │   browser_*      ──────►  Playwright MCP Proxy                  │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
          │                                              │
          │ Browserbase API                              │ MCP Proxy (stdio)
          ▼                                              ▼
┌─────────────────────────┐                 ┌─────────────────────────────┐
│   Browserbase Cloud     │                 │   @playwright/mcp           │
│                         │                 │   (npx subprocess)          │
│  • Session management   │◄────────────────│                             │
│  • Download storage     │    CDP/WSS      │  Connects to Browserbase    │
│  • Proxy infrastructure │                 │  via cdp_url                │
└─────────────────────────┘                 └─────────────────────────────┘
```

### Key Design Decisions

1. **FastMCP as_proxy()** - Forwards all Playwright MCP tools without reimplementing them
2. **Runtime env var reading** - Allows tests to mock credentials via monkeypatch
3. **CDP for downloads** - Uses Chrome DevTools Protocol to configure browser download behavior
4. **Polling for downloads** - Browserbase uploads files asynchronously; we poll until ready
5. **Base64 encoding** - Files returned as base64 for safe transport over MCP/JSON

---

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `BROWSERBASE_API_KEY` | Yes | Your Browserbase API key |
| `BROWSERBASE_PROJECT_ID` | Yes | Your Browserbase project ID |

Get these from [browserbase.com/settings](https://browserbase.com/settings).

---

## Development

### Running the Server Locally

```bash
# Start the server (stdio mode)
uv run fastmcp run src/clerkiq_playwright_mcp/server.py

# Or with environment variables
export $(grep -v '^#' .env | xargs) && uv run python -m clerkiq_playwright_mcp.server
```

### Adding New Tools

1. Add function to `src/clerkiq_playwright_mcp/tools/browserbase.py`
2. Register in `server.py` with `mcp.tool(your_function)`
3. Add tests in `tests/test_browserbase_tools.py`
4. Run tests: `uv run pytest tests/ -v`

---

## License

MIT

---

## Credits

- **[Browserbase](https://browserbase.com)** - Cloud browser infrastructure
- **[Playwright MCP](https://github.com/anthropics/mcp-server-playwright)** - Browser automation tools
- **[FastMCP](https://gofastmcp.com)** - MCP server framework
