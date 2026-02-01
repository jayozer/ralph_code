# Technical Design Document: ClerkIQ Custom Playwright MCP Server

## Document Information

| Field | Value |
|-------|-------|
| Author | ClerkIQ Team |
| Created | 2026-02-01 |
| Status | Draft |
| Version | 1.0 |

---

## 1. Executive Summary

This document describes the design and implementation of a custom MCP (Model Context Protocol) server that combines Playwright browser automation with Browserbase cloud browser support and download retrieval capabilities.

### Problem Statement

The official `@playwright/mcp` server does not expose a tool for retrieving files downloaded during browser automation sessions. When connected to a cloud browser provider like Browserbase:
- Downloads land in Browserbase's cloud storage
- There is no MCP tool to retrieve these files
- The `Browser.setDownloadBehavior` CDP command may be overridden

### Solution

Build a custom MCP server using **FastMCP** (Python) that:
1. Proxies all standard Playwright MCP tools
2. Adds Browserbase-specific tools for session management and download retrieval
3. Deploys to FastMCP/Prefect Horizon for cloud hosting

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    ClerkIQ Custom Playwright MCP                         │
│                         (FastMCP Python Server)                          │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                         MCP Proxy Provider                        │   │
│  │                                                                  │   │
│  │   Proxies all tools from @playwright/mcp:                       │   │
│  │   - playwright_navigate                                          │   │
│  │   - playwright_click                                             │   │
│  │   - playwright_fill                                              │   │
│  │   - playwright_screenshot                                        │   │
│  │   - ... (all standard Playwright tools)                         │   │
│  │                                                                  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                    Custom Browserbase Tools                       │   │
│  │                                                                  │   │
│  │   @mcp.tool                                                      │   │
│  │   def browserbase_create_session() -> BrowserbaseSession         │   │
│  │                                                                  │   │
│  │   @mcp.tool                                                      │   │
│  │   def browserbase_get_downloads(session_id) -> list[FileData]    │   │
│  │                                                                  │   │
│  │   @mcp.tool                                                      │   │
│  │   def browserbase_stop_session(session_id) -> bool              │   │
│  │                                                                  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
         ┌──────────────────────────────────────────────┐
         │              Browserbase API                  │
         │                                              │
         │  - POST /sessions (create session)           │
         │  - GET /sessions/{id}/downloads (get files)  │
         │  - POST /sessions/{id}/stop (stop session)   │
         └──────────────────────────────────────────────┘
```

---

## 3. Technology Stack

| Component | Technology | Rationale |
|-----------|------------|-----------|
| MCP Framework | **FastMCP 3.0** | Python-native, proxy provider, easy deployment |
| Browser Automation | `@playwright/mcp` (proxied) | Official Playwright MCP, well-maintained |
| Cloud Browser | Browserbase SDK | CDP access, Downloads API |
| Deployment | Prefect Horizon / FastMCP CLI | Free hosting for personal projects |
| Language | Python 3.11+ | Matches ClerkIQ codebase |

---

## 4. Detailed Design

### 4.1 Project Structure

```
clerkiq-playwright-mcp/
├── pyproject.toml              # UV/pip project configuration
├── fastmcp.json               # FastMCP project configuration
├── README.md                  # Documentation
├── src/
│   └── clerkiq_playwright_mcp/
│       ├── __init__.py
│       ├── server.py          # Main FastMCP server
│       ├── tools/
│       │   ├── __init__.py
│       │   └── browserbase.py # Browserbase tools
│       └── models/
│           ├── __init__.py
│           └── types.py       # Pydantic models
└── tests/
    ├── __init__.py
    └── test_tools.py
```

### 4.2 Core Components

#### 4.2.1 Main Server (`server.py`)

```python
from fastmcp import FastMCP
from fastmcp.server import create_proxy

from clerkiq_playwright_mcp.tools.browserbase import (
    browserbase_create_session,
    browserbase_get_downloads,
    browserbase_configure_downloads,
    browserbase_stop_session,
)

# Create the main server
mcp = FastMCP(name="ClerkIQ Playwright MCP")

# Proxy all Playwright MCP tools
# This forwards: playwright_navigate, playwright_click, etc.
playwright_proxy = create_proxy(
    {
        "mcpServers": {
            "playwright": {
                "command": "npx",
                "args": ["@playwright/mcp@latest", "--headless"],
                "transport": "stdio"
            }
        }
    },
    name="Playwright"
)

# Mount the Playwright proxy (all tools get "playwright_" prefix)
mcp.mount(playwright_proxy)

# Register custom Browserbase tools
mcp.add_tool(browserbase_create_session)
mcp.add_tool(browserbase_get_downloads)
mcp.add_tool(browserbase_configure_downloads)
mcp.add_tool(browserbase_stop_session)

if __name__ == "__main__":
    mcp.run()
```

#### 4.2.2 Browserbase Tools (`tools/browserbase.py`)

```python
import asyncio
import base64
import os
import zipfile
from io import BytesIO
from typing import Annotated

from pydantic import BaseModel, Field
from browserbase import Browserbase

# Environment variables
BROWSERBASE_API_KEY = os.environ.get("BROWSERBASE_API_KEY")
BROWSERBASE_PROJECT_ID = os.environ.get("BROWSERBASE_PROJECT_ID")


class BrowserbaseSession(BaseModel):
    """Response from creating a Browserbase session."""
    session_id: str = Field(description="The Browserbase session ID")
    cdp_url: str = Field(description="CDP websocket URL for Playwright connection")
    live_url: str | None = Field(default=None, description="Live view URL for debugging")


class DownloadedFile(BaseModel):
    """A file downloaded from Browserbase."""
    filename: str = Field(description="Original filename")
    content_base64: str = Field(description="File content as base64")
    size_bytes: int = Field(description="File size in bytes")


class DownloadsResult(BaseModel):
    """Result of retrieving downloads."""
    files: list[DownloadedFile] = Field(default_factory=list)
    total_files: int = Field(default=0)
    message: str = Field(default="")


def get_client() -> Browserbase:
    """Get or create Browserbase client."""
    if not BROWSERBASE_API_KEY:
        raise ValueError("BROWSERBASE_API_KEY environment variable not set")
    return Browserbase(api_key=BROWSERBASE_API_KEY)


async def browserbase_create_session(
    proxies: Annotated[bool, "Enable residential proxies"] = True,
    solve_captchas: Annotated[bool, "Enable automatic CAPTCHA solving"] = True,
    timeout_seconds: Annotated[int, "Session timeout in seconds"] = 1800,
) -> BrowserbaseSession:
    """
    Create a new Browserbase cloud browser session.

    Returns a session with CDP URL that can be used with playwright_navigate
    by configuring the browser to connect via CDP.

    After creating a session, use browserbase_configure_downloads to enable
    cloud download sync before navigating to pages.
    """
    if not BROWSERBASE_PROJECT_ID:
        raise ValueError("BROWSERBASE_PROJECT_ID environment variable not set")

    client = get_client()

    session = client.sessions.create(
        project_id=BROWSERBASE_PROJECT_ID,
        proxies=proxies,
        timeout=timeout_seconds,
        keep_alive=True,
        browser_settings={"solveCaptchas": solve_captchas},
    )

    return BrowserbaseSession(
        session_id=session.id,
        cdp_url=session.connect_url,
        live_url=getattr(session, "live_url", None),
    )


async def browserbase_configure_downloads(
    cdp_url: Annotated[str, "CDP websocket URL from browserbase_create_session"],
) -> bool:
    """
    Configure download behavior for a Browserbase session.

    This must be called AFTER connecting to the session but BEFORE
    triggering any downloads. It configures the browser to sync
    downloads to Browserbase's cloud storage.

    Returns True if configuration succeeded.
    """
    import json
    try:
        import websockets
    except ImportError:
        raise ImportError("websockets package required: pip install websockets")

    try:
        async with websockets.connect(cdp_url) as ws:
            cmd = {
                "id": 1,
                "method": "Browser.setDownloadBehavior",
                "params": {
                    "behavior": "allow",
                    "downloadPath": "downloads",  # Required by Browserbase
                    "eventsEnabled": True,
                }
            }
            await ws.send(json.dumps(cmd))
            response = await asyncio.wait_for(ws.recv(), timeout=10)
            result = json.loads(response)

            if "error" in result:
                return False
            return True

    except Exception:
        return False


async def browserbase_get_downloads(
    session_id: Annotated[str, "Browserbase session ID"],
    timeout_seconds: Annotated[int, "Max time to wait for downloads"] = 120,
    poll_interval: Annotated[float, "Seconds between poll attempts"] = 5.0,
) -> DownloadsResult:
    """
    Retrieve downloaded files from a Browserbase session.

    This polls the Browserbase Downloads API until files are available
    or timeout is reached. Files are returned as base64-encoded content.

    Call this AFTER the browser has completed downloading files
    (e.g., after clicking a download button and waiting).
    """
    client = get_client()

    MIN_ZIP_SIZE = 22  # Empty ZIP header size
    max_attempts = int(timeout_seconds / poll_interval)
    files: list[DownloadedFile] = []

    for attempt in range(max_attempts):
        try:
            response = client.sessions.downloads.list(session_id)
            content = response.read()

            if content and len(content) > MIN_ZIP_SIZE:
                try:
                    with zipfile.ZipFile(BytesIO(content)) as zf:
                        file_list = [
                            name for name in zf.namelist()
                            if not name.endswith("/") and not name.startswith(".")
                        ]

                        for name in file_list:
                            with zf.open(name) as f:
                                file_content = f.read()
                                files.append(DownloadedFile(
                                    filename=name.split("/")[-1],
                                    content_base64=base64.b64encode(file_content).decode(),
                                    size_bytes=len(file_content),
                                ))

                        if files:
                            return DownloadsResult(
                                files=files,
                                total_files=len(files),
                                message=f"Retrieved {len(files)} file(s)",
                            )
                except zipfile.BadZipFile:
                    pass  # Continue polling

            await asyncio.sleep(poll_interval)

        except Exception as e:
            if "404" in str(e):
                await asyncio.sleep(poll_interval)
                continue
            raise

    return DownloadsResult(
        files=[],
        total_files=0,
        message=f"No downloads found after {timeout_seconds}s",
    )


async def browserbase_stop_session(
    session_id: Annotated[str, "Browserbase session ID"],
) -> bool:
    """
    Stop a Browserbase session and release resources.

    Sessions auto-expire, but stopping early releases resources
    and may reduce costs.

    Returns True if session was stopped successfully.
    """
    try:
        client = get_client()
        client.sessions.update(
            session_id,
            project_id=BROWSERBASE_PROJECT_ID,
            status="REQUEST_RELEASE",
        )
        return True
    except Exception:
        return False
```

#### 4.2.3 Type Models (`models/types.py`)

```python
from pydantic import BaseModel, Field
from typing import Optional


class BrowserbaseConfig(BaseModel):
    """Configuration for Browserbase connection."""
    api_key: str = Field(description="Browserbase API key")
    project_id: str = Field(description="Browserbase project ID")


class SessionInfo(BaseModel):
    """Information about an active session."""
    session_id: str
    cdp_url: str
    is_configured: bool = False
    download_count: int = 0
```

### 4.3 FastMCP Project Configuration

#### `fastmcp.json`

```json
{
  "$schema": "https://gofastmcp.com/public/schemas/fastmcp.json/v1.json",
  "source": {
    "path": "src/clerkiq_playwright_mcp/server.py",
    "entrypoint": "mcp"
  },
  "environment": {
    "dependencies": [
      "browserbase",
      "websockets",
      "pydantic>=2.0"
    ]
  },
  "server": {
    "name": "clerkiq-playwright"
  }
}
```

#### `pyproject.toml`

```toml
[project]
name = "clerkiq-playwright-mcp"
version = "0.1.0"
description = "Custom Playwright MCP with Browserbase download support"
requires-python = ">=3.11"
dependencies = [
    "fastmcp>=3.0.0",
    "browserbase>=1.0.0",
    "websockets>=12.0",
    "pydantic>=2.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=0.23",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.uv]
dev-dependencies = [
    "pytest>=8.0",
    "pytest-asyncio>=0.23",
]
```

---

## 5. Implementation Steps

### Phase 1: Project Setup (Day 1)

1. **Create new repository**
   ```bash
   mkdir clerkiq-playwright-mcp
   cd clerkiq-playwright-mcp
   git init
   ```

2. **Initialize UV project**
   ```bash
   uv init
   uv add fastmcp browserbase websockets pydantic
   ```

3. **Create directory structure**
   ```bash
   mkdir -p src/clerkiq_playwright_mcp/tools
   mkdir -p src/clerkiq_playwright_mcp/models
   mkdir -p tests
   touch src/clerkiq_playwright_mcp/__init__.py
   touch src/clerkiq_playwright_mcp/tools/__init__.py
   touch src/clerkiq_playwright_mcp/models/__init__.py
   ```

### Phase 2: Core Implementation (Day 1-2)

1. **Implement Browserbase tools** (`tools/browserbase.py`)
   - `browserbase_create_session`
   - `browserbase_configure_downloads`
   - `browserbase_get_downloads`
   - `browserbase_stop_session`

2. **Create main server** (`server.py`)
   - Set up FastMCP server
   - Configure Playwright MCP proxy
   - Register custom tools

3. **Add type models** (`models/types.py`)

### Phase 3: Testing (Day 2)

1. **Unit tests for tools**
   ```python
   # tests/test_tools.py
   import pytest
   from clerkiq_playwright_mcp.tools.browserbase import (
       browserbase_create_session,
       browserbase_get_downloads,
   )

   @pytest.mark.asyncio
   async def test_create_session():
       # Test with mock
       pass

   @pytest.mark.asyncio
   async def test_get_downloads_empty():
       # Test empty response
       pass
   ```

2. **Integration test with real Browserbase**
   ```bash
   export BROWSERBASE_API_KEY=your-key
   export BROWSERBASE_PROJECT_ID=your-project
   pytest tests/ -v
   ```

### Phase 4: Local Testing with Claude Code (Day 2-3)

1. **Run server locally**
   ```bash
   fastmcp run src/clerkiq_playwright_mcp/server.py
   ```

2. **Install in Claude Code**
   ```bash
   fastmcp install claude-code src/clerkiq_playwright_mcp/server.py \
     --with browserbase --with websockets \
     --env BROWSERBASE_API_KEY=your-key \
     --env BROWSERBASE_PROJECT_ID=your-project
   ```

3. **Test with Claude**
   - "Create a Browserbase session"
   - "Navigate to https://example.com"
   - "Click the download button"
   - "Get downloads from the session"

### Phase 5: Deployment to FastMCP (Day 3)

1. **Push to GitHub**
   ```bash
   git add .
   git commit -m "Initial implementation"
   git push origin main
   ```

2. **Deploy to Prefect Horizon**
   - Sign in to [horizon.prefect.io](https://horizon.prefect.io)
   - Create new project from GitHub repo
   - Set entrypoint: `src/clerkiq_playwright_mcp/server.py:mcp`
   - Configure environment variables

3. **Configure in ClerkIQ**
   ```python
   # In ClerkIQ config
   MCP_SERVERS = {
       "clerkiq-playwright": {
           "url": "https://your-project.fastmcp.app/mcp",
           "transport": "http"
       }
   }
   ```

---

## 6. Usage Workflow

### 6.1 Complete Document Download Workflow

```
1. Agent: browserbase_create_session()
   → Returns: { session_id, cdp_url }

2. Agent: browserbase_configure_downloads(cdp_url)
   → Configures download behavior for cloud storage

3. Agent: playwright_navigate(url="https://clerk.county.gov/search")
   → Connects to Browserbase session via CDP

4. Agent: playwright_fill(selector="#search", text="document-number")
   → Fills search form

5. Agent: playwright_click(selector="#search-btn")
   → Submits search

6. Agent: playwright_click(selector=".download-btn")
   → Clicks download button

7. Agent: [wait for download]

8. Agent: browserbase_get_downloads(session_id)
   → Returns: { files: [{ filename, content_base64, size_bytes }] }

9. Agent: browserbase_stop_session(session_id)
   → Releases resources
```

### 6.2 Integration with Claude Agent SDK

```python
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

options = ClaudeAgentOptions(
    mcp_servers={
        "clerkiq-playwright": {
            "url": "https://your-project.fastmcp.app/mcp",
            "transport": "http"
        }
    },
    allowed_tools=["mcp__clerkiq-playwright__*"],
)

prompt = """
1. Create a Browserbase session
2. Configure downloads for the session
3. Navigate to https://bexar.tx.publicsearch.us/
4. Search for document number 20230058453
5. Download the document
6. Get the downloaded files from Browserbase
7. Stop the session
"""

async with ClaudeSDKClient(options=options) as client:
    result = await client.query(prompt)
```

---

## 7. Deployment Options

### Option A: Prefect Horizon (Recommended)

**Pros:**
- Free for personal projects
- Automatic HTTPS
- Built-in monitoring
- Easy GitHub integration

**Steps:**
1. Push to GitHub
2. Connect repo to Prefect Horizon
3. Deploy

### Option B: Self-Hosted HTTP

**Pros:**
- Full control
- No external dependencies

**Steps:**
```bash
fastmcp run server.py --transport http --port 8000 --host 0.0.0.0
```

### Option C: Claude Code Local (Development)

**Pros:**
- Fast iteration
- No deployment needed

**Steps:**
```bash
fastmcp install claude-code server.py --env-file .env
```

---

## 8. Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `BROWSERBASE_API_KEY` | Yes | Browserbase API key |
| `BROWSERBASE_PROJECT_ID` | Yes | Browserbase project ID |

---

## 9. Testing Strategy

### 9.1 Unit Tests

```python
# tests/test_browserbase_tools.py
import pytest
from unittest.mock import Mock, patch

@pytest.mark.asyncio
async def test_create_session_success():
    """Test successful session creation."""
    with patch("browserbase.Browserbase") as mock_bb:
        mock_session = Mock()
        mock_session.id = "test-session-id"
        mock_session.connect_url = "wss://connect.browserbase.com/..."
        mock_bb.return_value.sessions.create.return_value = mock_session

        result = await browserbase_create_session()

        assert result.session_id == "test-session-id"
        assert "wss://" in result.cdp_url

@pytest.mark.asyncio
async def test_get_downloads_empty():
    """Test handling of no downloads."""
    with patch("browserbase.Browserbase") as mock_bb:
        mock_response = Mock()
        mock_response.read.return_value = b""
        mock_bb.return_value.sessions.downloads.list.return_value = mock_response

        result = await browserbase_get_downloads("test-session", timeout_seconds=1)

        assert result.total_files == 0
```

### 9.2 Integration Tests

```python
# tests/test_integration.py
import pytest
import os

pytestmark = pytest.mark.skipif(
    not os.environ.get("BROWSERBASE_API_KEY"),
    reason="Browserbase credentials not configured"
)

@pytest.mark.asyncio
async def test_full_session_lifecycle():
    """Test creating session, downloading, and stopping."""
    # Create session
    session = await browserbase_create_session()
    assert session.session_id

    # Configure downloads
    configured = await browserbase_configure_downloads(session.cdp_url)
    assert configured

    # Stop session
    stopped = await browserbase_stop_session(session.session_id)
    assert stopped
```

---

## 10. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Playwright MCP proxy adds latency | Medium | Medium | Cache tool definitions; use `import_server()` for static tools |
| Browserbase API rate limits | Low | High | Implement exponential backoff; pool sessions |
| CDP configuration still overridden | Medium | High | Configure after first Playwright tool; use hooks |
| File size exceeds MCP message limits | Low | Medium | Return file references instead of content; use resources |

---

## 11. Success Criteria

1. **Functional Requirements**
   - [ ] Can create Browserbase sessions via MCP tool
   - [ ] Can configure download behavior via MCP tool
   - [ ] Can retrieve downloaded files via MCP tool
   - [ ] All Playwright tools work through proxy
   - [ ] Deploys successfully to Prefect Horizon

2. **Non-Functional Requirements**
   - [ ] Tool execution < 5s for session operations
   - [ ] Download retrieval supports files up to 50MB
   - [ ] Works with Claude Agent SDK
   - [ ] Works with Claude Code

---

## 12. Timeline

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| Setup | 4 hours | Project structure, dependencies |
| Implementation | 8 hours | All tools, server, tests |
| Testing | 4 hours | Unit tests, integration tests |
| Deployment | 2 hours | Prefect Horizon deployment |
| Integration | 4 hours | ClerkIQ integration |

**Total: ~22 hours (3 days)**

---

## 13. Complete File Contents

This section contains all files needed to build and test the project from scratch.

### 13.1 `requirements.txt`

```
fastmcp>=3.0.0
browserbase>=1.0.0
websockets>=12.0
pydantic>=2.0
pytest>=8.0
pytest-asyncio>=0.23
```

### 13.2 `.env.example`

```bash
# Browserbase credentials (required)
BROWSERBASE_API_KEY=your-api-key-here
BROWSERBASE_PROJECT_ID=your-project-id-here
```

### 13.3 `src/clerkiq_playwright_mcp/__init__.py`

```python
"""ClerkIQ Custom Playwright MCP Server with Browserbase support."""

__version__ = "0.1.0"
```

### 13.4 `src/clerkiq_playwright_mcp/tools/__init__.py`

```python
"""Browserbase tools for MCP server."""

from .browserbase import (
    browserbase_create_session,
    browserbase_configure_downloads,
    browserbase_get_downloads,
    browserbase_stop_session,
)

__all__ = [
    "browserbase_create_session",
    "browserbase_configure_downloads",
    "browserbase_get_downloads",
    "browserbase_stop_session",
]
```

### 13.5 `src/clerkiq_playwright_mcp/models/__init__.py`

```python
"""Pydantic models for MCP responses."""

from .types import BrowserbaseConfig, SessionInfo

__all__ = ["BrowserbaseConfig", "SessionInfo"]
```

### 13.6 `tests/__init__.py`

```python
"""Test suite for ClerkIQ Playwright MCP."""
```

### 13.7 `tests/conftest.py`

```python
"""Pytest fixtures for testing Browserbase tools."""

import pytest
from unittest.mock import Mock, AsyncMock, patch
import os


@pytest.fixture(autouse=True)
def mock_env_vars(monkeypatch):
    """Set required environment variables for tests."""
    monkeypatch.setenv("BROWSERBASE_API_KEY", "test-api-key")
    monkeypatch.setenv("BROWSERBASE_PROJECT_ID", "test-project-id")


@pytest.fixture
def mock_browserbase_client():
    """Create a mock Browserbase client."""
    with patch("clerkiq_playwright_mcp.tools.browserbase.Browserbase") as mock:
        client = Mock()
        mock.return_value = client
        yield client


@pytest.fixture
def mock_session():
    """Create a mock Browserbase session."""
    session = Mock()
    session.id = "test-session-123"
    session.connect_url = "wss://connect.browserbase.com/test"
    session.live_url = "https://live.browserbase.com/test"
    return session


@pytest.fixture
def mock_websocket():
    """Create a mock websocket connection."""
    with patch("websockets.connect") as mock:
        ws = AsyncMock()
        ws.recv = AsyncMock(return_value='{"id": 1, "result": {}}')
        mock.return_value.__aenter__.return_value = ws
        yield ws


@pytest.fixture
def sample_zip_with_pdf():
    """Create a sample ZIP file containing a PDF for testing downloads."""
    import io
    import zipfile

    # Create a minimal PDF-like content
    pdf_content = b"%PDF-1.4\n1 0 obj\n<<>>\nendobj\nxref\n0 0\ntrailer\n<<>>\nstartxref\n0\n%%EOF"

    # Create ZIP in memory
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("downloads/test_document.pdf", pdf_content)

    return zip_buffer.getvalue()
```

### 13.8 `pytest.ini`

```ini
[pytest]
asyncio_mode = auto
testpaths = tests
python_files = test_*.py
python_functions = test_*
addopts = -v --tb=short
```

### 13.9 `.gitignore`

```
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg

# Virtual environments
.venv/
venv/
ENV/

# IDE
.idea/
.vscode/
*.swp
*.swo

# Testing
.pytest_cache/
.coverage
htmlcov/

# Environment
.env
.env.local

# UV
.uv/
uv.lock
```

---

## 14. Complete Test Suite

### 14.1 `tests/test_browserbase_tools.py`

```python
"""Unit tests for Browserbase tools."""

import pytest
import base64
from unittest.mock import Mock, AsyncMock, patch, MagicMock

# Import will be done after mocking env vars in conftest


class TestBrowserbaseCreateSession:
    """Tests for browserbase_create_session."""

    @pytest.mark.asyncio
    async def test_create_session_success(self, mock_browserbase_client, mock_session):
        """Test successful session creation."""
        mock_browserbase_client.sessions.create.return_value = mock_session

        # Import after env vars are set by fixture
        from clerkiq_playwright_mcp.tools.browserbase import browserbase_create_session

        result = await browserbase_create_session()

        assert result.session_id == "test-session-123"
        assert "wss://" in result.cdp_url
        assert result.live_url == "https://live.browserbase.com/test"

        # Verify create was called with correct args
        mock_browserbase_client.sessions.create.assert_called_once()
        call_kwargs = mock_browserbase_client.sessions.create.call_args.kwargs
        assert call_kwargs["project_id"] == "test-project-id"
        assert call_kwargs["proxies"] is True
        assert call_kwargs["keep_alive"] is True

    @pytest.mark.asyncio
    async def test_create_session_custom_params(self, mock_browserbase_client, mock_session):
        """Test session creation with custom parameters."""
        mock_browserbase_client.sessions.create.return_value = mock_session

        from clerkiq_playwright_mcp.tools.browserbase import browserbase_create_session

        result = await browserbase_create_session(
            proxies=False,
            solve_captchas=False,
            timeout_seconds=3600
        )

        assert result.session_id == "test-session-123"

        call_kwargs = mock_browserbase_client.sessions.create.call_args.kwargs
        assert call_kwargs["proxies"] is False
        assert call_kwargs["timeout"] == 3600

    @pytest.mark.asyncio
    async def test_create_session_missing_api_key(self, monkeypatch):
        """Test error when API key is missing."""
        monkeypatch.delenv("BROWSERBASE_API_KEY", raising=False)

        # Need to reimport to pick up the missing env var
        import importlib
        import clerkiq_playwright_mcp.tools.browserbase as bb_module
        importlib.reload(bb_module)

        with pytest.raises(ValueError, match="BROWSERBASE_API_KEY"):
            await bb_module.browserbase_create_session()


class TestBrowserbaseConfigureDownloads:
    """Tests for browserbase_configure_downloads."""

    @pytest.mark.asyncio
    async def test_configure_downloads_success(self, mock_websocket):
        """Test successful download configuration."""
        from clerkiq_playwright_mcp.tools.browserbase import browserbase_configure_downloads

        result = await browserbase_configure_downloads(
            cdp_url="wss://connect.browserbase.com/test"
        )

        assert result is True

        # Verify the CDP command was sent
        mock_websocket.send.assert_called_once()
        import json
        sent_data = json.loads(mock_websocket.send.call_args[0][0])
        assert sent_data["method"] == "Browser.setDownloadBehavior"
        assert sent_data["params"]["behavior"] == "allow"
        assert sent_data["params"]["downloadPath"] == "downloads"

    @pytest.mark.asyncio
    async def test_configure_downloads_error_response(self, mock_websocket):
        """Test handling of CDP error response."""
        mock_websocket.recv = AsyncMock(
            return_value='{"id": 1, "error": {"code": -32000, "message": "Failed"}}'
        )

        from clerkiq_playwright_mcp.tools.browserbase import browserbase_configure_downloads

        result = await browserbase_configure_downloads(
            cdp_url="wss://connect.browserbase.com/test"
        )

        assert result is False

    @pytest.mark.asyncio
    async def test_configure_downloads_connection_error(self):
        """Test handling of websocket connection error."""
        with patch("websockets.connect", side_effect=ConnectionRefusedError()):
            from clerkiq_playwright_mcp.tools.browserbase import browserbase_configure_downloads

            result = await browserbase_configure_downloads(
                cdp_url="wss://invalid.url/test"
            )

            assert result is False


class TestBrowserbaseGetDownloads:
    """Tests for browserbase_get_downloads."""

    @pytest.mark.asyncio
    async def test_get_downloads_success(self, mock_browserbase_client, sample_zip_with_pdf):
        """Test successful download retrieval."""
        mock_response = Mock()
        mock_response.read.return_value = sample_zip_with_pdf
        mock_browserbase_client.sessions.downloads.list.return_value = mock_response

        from clerkiq_playwright_mcp.tools.browserbase import browserbase_get_downloads

        result = await browserbase_get_downloads(
            session_id="test-session-123",
            timeout_seconds=5,
            poll_interval=0.1
        )

        assert result.total_files == 1
        assert len(result.files) == 1
        assert result.files[0].filename == "test_document.pdf"
        assert result.files[0].size_bytes > 0

        # Verify content is valid base64
        decoded = base64.b64decode(result.files[0].content_base64)
        assert decoded.startswith(b"%PDF")

    @pytest.mark.asyncio
    async def test_get_downloads_empty(self, mock_browserbase_client):
        """Test handling of no downloads."""
        mock_response = Mock()
        mock_response.read.return_value = b""
        mock_browserbase_client.sessions.downloads.list.return_value = mock_response

        from clerkiq_playwright_mcp.tools.browserbase import browserbase_get_downloads

        result = await browserbase_get_downloads(
            session_id="test-session-123",
            timeout_seconds=1,
            poll_interval=0.1
        )

        assert result.total_files == 0
        assert len(result.files) == 0
        assert "No downloads found" in result.message

    @pytest.mark.asyncio
    async def test_get_downloads_404_then_success(self, mock_browserbase_client, sample_zip_with_pdf):
        """Test polling when initial requests return 404."""
        call_count = 0

        def mock_list(session_id):
            nonlocal call_count
            call_count += 1
            if call_count < 3:
                raise Exception("404 Not Found")
            mock_response = Mock()
            mock_response.read.return_value = sample_zip_with_pdf
            return mock_response

        mock_browserbase_client.sessions.downloads.list.side_effect = mock_list

        from clerkiq_playwright_mcp.tools.browserbase import browserbase_get_downloads

        result = await browserbase_get_downloads(
            session_id="test-session-123",
            timeout_seconds=10,
            poll_interval=0.1
        )

        assert result.total_files == 1
        assert call_count == 3


class TestBrowserbaseStopSession:
    """Tests for browserbase_stop_session."""

    @pytest.mark.asyncio
    async def test_stop_session_success(self, mock_browserbase_client):
        """Test successful session stop."""
        mock_browserbase_client.sessions.update.return_value = None

        from clerkiq_playwright_mcp.tools.browserbase import browserbase_stop_session

        result = await browserbase_stop_session(session_id="test-session-123")

        assert result is True
        mock_browserbase_client.sessions.update.assert_called_once_with(
            "test-session-123",
            project_id="test-project-id",
            status="REQUEST_RELEASE",
        )

    @pytest.mark.asyncio
    async def test_stop_session_error(self, mock_browserbase_client):
        """Test handling of stop session error."""
        mock_browserbase_client.sessions.update.side_effect = Exception("API Error")

        from clerkiq_playwright_mcp.tools.browserbase import browserbase_stop_session

        result = await browserbase_stop_session(session_id="test-session-123")

        assert result is False
```

### 14.2 `tests/test_server.py`

```python
"""Tests for the FastMCP server configuration."""

import pytest
from unittest.mock import patch, Mock


class TestServerSetup:
    """Tests for server initialization."""

    def test_server_has_custom_tools(self):
        """Verify custom Browserbase tools are registered."""
        with patch.dict("os.environ", {
            "BROWSERBASE_API_KEY": "test-key",
            "BROWSERBASE_PROJECT_ID": "test-project"
        }):
            from clerkiq_playwright_mcp.server import mcp

            # Get registered tools
            tools = mcp.list_tools() if hasattr(mcp, 'list_tools') else []
            tool_names = [t.name if hasattr(t, 'name') else str(t) for t in tools]

            # Check custom tools are registered
            expected_tools = [
                "browserbase_create_session",
                "browserbase_configure_downloads",
                "browserbase_get_downloads",
                "browserbase_stop_session",
            ]

            for tool in expected_tools:
                assert any(tool in name for name in tool_names), f"Missing tool: {tool}"

    def test_server_name(self):
        """Verify server name is set correctly."""
        with patch.dict("os.environ", {
            "BROWSERBASE_API_KEY": "test-key",
            "BROWSERBASE_PROJECT_ID": "test-project"
        }):
            from clerkiq_playwright_mcp.server import mcp

            assert mcp.name == "ClerkIQ Playwright MCP"
```

### 14.3 `tests/test_models.py`

```python
"""Tests for Pydantic models."""

import pytest
from pydantic import ValidationError


class TestModels:
    """Tests for type models."""

    def test_browserbase_session_model(self):
        """Test BrowserbaseSession model."""
        from clerkiq_playwright_mcp.tools.browserbase import BrowserbaseSession

        session = BrowserbaseSession(
            session_id="sess-123",
            cdp_url="wss://connect.browserbase.com/sess-123",
            live_url="https://live.browserbase.com/sess-123"
        )

        assert session.session_id == "sess-123"
        assert "wss://" in session.cdp_url
        assert session.live_url is not None

    def test_browserbase_session_optional_live_url(self):
        """Test BrowserbaseSession with optional live_url."""
        from clerkiq_playwright_mcp.tools.browserbase import BrowserbaseSession

        session = BrowserbaseSession(
            session_id="sess-123",
            cdp_url="wss://connect.browserbase.com/sess-123"
        )

        assert session.live_url is None

    def test_downloaded_file_model(self):
        """Test DownloadedFile model."""
        from clerkiq_playwright_mcp.tools.browserbase import DownloadedFile

        file = DownloadedFile(
            filename="test.pdf",
            content_base64="dGVzdA==",  # "test" in base64
            size_bytes=4
        )

        assert file.filename == "test.pdf"
        assert file.size_bytes == 4

    def test_downloads_result_model(self):
        """Test DownloadsResult model."""
        from clerkiq_playwright_mcp.tools.browserbase import DownloadsResult, DownloadedFile

        result = DownloadsResult(
            files=[
                DownloadedFile(
                    filename="doc1.pdf",
                    content_base64="YWJj",
                    size_bytes=3
                )
            ],
            total_files=1,
            message="Retrieved 1 file(s)"
        )

        assert result.total_files == 1
        assert len(result.files) == 1
        assert result.files[0].filename == "doc1.pdf"

    def test_downloads_result_empty(self):
        """Test empty DownloadsResult."""
        from clerkiq_playwright_mcp.tools.browserbase import DownloadsResult

        result = DownloadsResult()

        assert result.total_files == 0
        assert result.files == []
        assert result.message == ""

    def test_browserbase_config_model(self):
        """Test BrowserbaseConfig model."""
        from clerkiq_playwright_mcp.models.types import BrowserbaseConfig

        config = BrowserbaseConfig(
            api_key="sk-test-123",
            project_id="proj-456"
        )

        assert config.api_key == "sk-test-123"
        assert config.project_id == "proj-456"

    def test_session_info_model(self):
        """Test SessionInfo model."""
        from clerkiq_playwright_mcp.models.types import SessionInfo

        info = SessionInfo(
            session_id="sess-123",
            cdp_url="wss://example.com",
            is_configured=True,
            download_count=5
        )

        assert info.session_id == "sess-123"
        assert info.is_configured is True
        assert info.download_count == 5

    def test_session_info_defaults(self):
        """Test SessionInfo default values."""
        from clerkiq_playwright_mcp.models.types import SessionInfo

        info = SessionInfo(
            session_id="sess-123",
            cdp_url="wss://example.com"
        )

        assert info.is_configured is False
        assert info.download_count == 0
```

### 14.4 `tests/test_integration.py`

```python
"""Integration tests that require real Browserbase credentials.

These tests are skipped unless BROWSERBASE_API_KEY and BROWSERBASE_PROJECT_ID
are set in the environment.

Run with:
    BROWSERBASE_API_KEY=your-key BROWSERBASE_PROJECT_ID=your-project pytest tests/test_integration.py -v
"""

import pytest
import os

# Skip all tests in this module if credentials not configured
pytestmark = pytest.mark.skipif(
    not os.environ.get("BROWSERBASE_API_KEY") or not os.environ.get("BROWSERBASE_PROJECT_ID"),
    reason="Browserbase credentials not configured"
)


class TestIntegration:
    """Integration tests with real Browserbase."""

    @pytest.mark.asyncio
    async def test_full_session_lifecycle(self):
        """Test creating, configuring, and stopping a session."""
        from clerkiq_playwright_mcp.tools.browserbase import (
            browserbase_create_session,
            browserbase_configure_downloads,
            browserbase_stop_session,
        )

        # Create session
        session = await browserbase_create_session(
            timeout_seconds=300  # Short timeout for test
        )
        assert session.session_id
        assert session.cdp_url.startswith("wss://")

        try:
            # Configure downloads
            configured = await browserbase_configure_downloads(session.cdp_url)
            assert configured is True

        finally:
            # Always stop session
            stopped = await browserbase_stop_session(session.session_id)
            assert stopped is True

    @pytest.mark.asyncio
    async def test_get_downloads_no_files(self):
        """Test get_downloads returns empty when no files downloaded."""
        from clerkiq_playwright_mcp.tools.browserbase import (
            browserbase_create_session,
            browserbase_get_downloads,
            browserbase_stop_session,
        )

        session = await browserbase_create_session(timeout_seconds=300)

        try:
            # Get downloads without downloading anything
            result = await browserbase_get_downloads(
                session_id=session.session_id,
                timeout_seconds=5,
                poll_interval=1.0
            )

            assert result.total_files == 0
            assert "No downloads found" in result.message

        finally:
            await browserbase_stop_session(session.session_id)
```

---

## 15. README.md

```markdown
# ClerkIQ Custom Playwright MCP

Custom MCP server that combines Playwright browser automation with Browserbase cloud browser support and download retrieval.

## Overview

This MCP server solves a critical limitation: the official `@playwright/mcp` does not support retrieving downloaded files from cloud browser sessions. This server:

1. **Proxies all Playwright tools** - Full access to navigation, clicking, form filling, screenshots
2. **Adds Browserbase tools** - Session creation, download configuration, file retrieval
3. **Handles cloud downloads** - Retrieves files from Browserbase's cloud storage

## Quick Start

### Prerequisites

- Python 3.11+
- Node.js (for npx/Playwright MCP)
- Browserbase account ([sign up](https://browserbase.com))

### Installation

```bash
# Clone the repository
git clone https://github.com/your-org/clerkiq-playwright-mcp.git
cd clerkiq-playwright-mcp

# Create virtual environment and install dependencies
uv venv
uv pip install -e ".[dev]"

# Or with pip
pip install -e ".[dev]"

# Copy environment template
cp .env.example .env
# Edit .env with your Browserbase credentials
```

### Running Tests

```bash
# Run all unit tests
pytest

# Run with coverage
pytest --cov=src/clerkiq_playwright_mcp

# Run integration tests (requires real Browserbase credentials)
BROWSERBASE_API_KEY=your-key BROWSERBASE_PROJECT_ID=your-project pytest tests/test_integration.py -v
```

### Local Development

```bash
# Run the MCP server locally
fastmcp run src/clerkiq_playwright_mcp/server.py

# Install in Claude Code for testing
fastmcp install claude-code src/clerkiq_playwright_mcp/server.py \
  --with browserbase --with websockets \
  --env-file .env
```

### Deployment to Prefect Horizon

1. Push to GitHub
2. Go to [horizon.prefect.io](https://horizon.prefect.io)
3. Create new project from your GitHub repo
4. Set entrypoint: `src/clerkiq_playwright_mcp/server.py:mcp`
5. Configure environment variables:
   - `BROWSERBASE_API_KEY`
   - `BROWSERBASE_PROJECT_ID`

## Available Tools

### Browserbase Tools

| Tool | Description |
|------|-------------|
| `browserbase_create_session` | Create a new Browserbase cloud browser session |
| `browserbase_configure_downloads` | Configure download behavior for cloud storage |
| `browserbase_get_downloads` | Retrieve downloaded files from Browserbase |
| `browserbase_stop_session` | Stop a session and release resources |

### Proxied Playwright Tools

All standard `@playwright/mcp` tools are available:
- `playwright_navigate` - Navigate to URLs
- `playwright_click` - Click elements
- `playwright_fill` - Fill form inputs
- `playwright_screenshot` - Take screenshots
- And more...

## Usage Example

```python
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

options = ClaudeAgentOptions(
    mcp_servers={
        "clerkiq-playwright": {
            "url": "https://your-project.fastmcp.app/mcp",
            "transport": "http"
        }
    },
    allowed_tools=["mcp__clerkiq-playwright__*"],
)

prompt = """
1. Create a Browserbase session
2. Configure downloads for the session
3. Navigate to https://example.com/documents
4. Click the download button
5. Get the downloaded files from Browserbase
6. Stop the session
"""

async with ClaudeSDKClient(options=options) as client:
    result = await client.query(prompt)
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  ClerkIQ Playwright MCP                      │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │              MCP Proxy Provider                      │   │
│   │   Forwards: playwright_navigate, playwright_click,  │   │
│   │   playwright_fill, playwright_screenshot, etc.       │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │           Custom Browserbase Tools                   │   │
│   │   browserbase_create_session                         │   │
│   │   browserbase_configure_downloads                    │   │
│   │   browserbase_get_downloads                          │   │
│   │   browserbase_stop_session                           │   │
│   └─────────────────────────────────────────────────────┘   │
│                           │                                 │
└───────────────────────────│─────────────────────────────────┘
                            ▼
               ┌───────────────────────┐
               │    Browserbase API    │
               │  - Create sessions    │
               │  - Get downloads      │
               │  - Stop sessions      │
               └───────────────────────┘
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `BROWSERBASE_API_KEY` | Yes | Your Browserbase API key |
| `BROWSERBASE_PROJECT_ID` | Yes | Your Browserbase project ID |

## License

MIT
```

---

## 16. References

- [FastMCP Documentation](https://gofastmcp.com)
- [FastMCP Proxy Provider](https://gofastmcp.com/servers/providers/proxy)
- [FastMCP Claude Code Integration](https://gofastmcp.com/integrations/claude-code)
- [Browserbase Documentation](https://docs.browserbase.com)
- [Playwright MCP](https://github.com/anthropics/anthropic-tools/tree/main/playwright-mcp)
- [MCP Protocol Specification](https://modelcontextprotocol.io)
