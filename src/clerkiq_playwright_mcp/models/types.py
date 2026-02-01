"""Pydantic type models for ClerkIQ Playwright MCP.

Per TDD section 4.2.3 - Type definitions for Browserbase configuration and session state.
"""

from pydantic import BaseModel


class BrowserbaseConfig(BaseModel):
    """Configuration for Browserbase API authentication."""

    api_key: str
    project_id: str


class SessionInfo(BaseModel):
    """Session state information for tracking active browser sessions."""

    session_id: str
    cdp_url: str
    is_configured: bool = False
    download_count: int = 0
