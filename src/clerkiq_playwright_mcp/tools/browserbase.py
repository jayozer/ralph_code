"""Browserbase tools for MCP server.

Per TDD section 4.2.2 - Tools for managing Browserbase cloud browser sessions.
"""

import asyncio
import json
import os
from typing import Annotated

import websockets
from pydantic import BaseModel, Field
from browserbase import Browserbase
from browserbase.types.session_create_params import BrowserSettings


# Environment variables - read at module level for get_client()
BROWSERBASE_API_KEY = os.environ.get("BROWSERBASE_API_KEY")
BROWSERBASE_PROJECT_ID = os.environ.get("BROWSERBASE_PROJECT_ID")


class BrowserbaseSession(BaseModel):
    """Response from creating a Browserbase session."""

    session_id: str = Field(description="The Browserbase session ID")
    cdp_url: str = Field(description="CDP websocket URL for Playwright connection")
    live_url: str | None = Field(
        default=None, description="Live view URL for debugging"
    )


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
        browser_settings=BrowserSettings(solve_captchas=solve_captchas),
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

    Must be called AFTER connecting to the session but BEFORE triggering any downloads.
    This enables downloads to be synced to Browserbase cloud storage for later retrieval.

    Args:
        cdp_url: The CDP websocket URL from browserbase_create_session

    Returns:
        True if downloads configured successfully, False on error
    """
    try:
        async with websockets.connect(cdp_url) as ws:
            # Send Browser.setDownloadBehavior CDP command
            command = {
                "id": 1,
                "method": "Browser.setDownloadBehavior",
                "params": {
                    "behavior": "allow",
                    "downloadPath": "downloads",
                    "eventsEnabled": True,
                },
            }
            await ws.send(json.dumps(command))

            # Wait for response with 10 second timeout
            response_str = await asyncio.wait_for(ws.recv(), timeout=10.0)
            response = json.loads(response_str)

            # Check for error in CDP response
            if "error" in response:
                return False

            return True

    except (websockets.exceptions.WebSocketException, asyncio.TimeoutError, OSError):
        return False
