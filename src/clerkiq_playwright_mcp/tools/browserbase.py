"""Browserbase tools for MCP server.

Per TDD section 4.2.2 - Tools for managing Browserbase cloud browser sessions.
"""

import asyncio
import base64
import io
import json
import os
import zipfile
from typing import Annotated

import websockets
from pydantic import BaseModel, Field
from browserbase import Browserbase
from browserbase.types.session_create_params import BrowserSettings


# Minimum valid ZIP file size (empty ZIP is 22 bytes)
MIN_ZIP_SIZE = 22


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


class DownloadedFile(BaseModel):
    """A single downloaded file from Browserbase session."""

    filename: str = Field(description="Name of the downloaded file")
    content_base64: str = Field(description="Base64-encoded file content")
    size_bytes: int = Field(description="Size of the file in bytes")


class DownloadsResult(BaseModel):
    """Result from retrieving downloads from a Browserbase session."""

    files: list[DownloadedFile] = Field(
        default_factory=list, description="List of downloaded files"
    )
    total_files: int = Field(default=0, description="Total number of files retrieved")
    message: str = Field(default="", description="Status message")


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


async def browserbase_get_downloads(
    session_id: Annotated[str, "The Browserbase session ID"],
    timeout_seconds: Annotated[int, "Timeout in seconds to wait for downloads"] = 120,
    poll_interval: Annotated[float, "Interval in seconds between polling attempts"] = 5.0,
) -> DownloadsResult:
    """
    Retrieve downloaded files from a Browserbase session.

    Polls the Browserbase Downloads API until files are available or timeout is reached.
    Files are returned as base64-encoded content for easy transport.

    Args:
        session_id: The Browserbase session ID from browserbase_create_session
        timeout_seconds: Maximum time to wait for downloads (default 120s)
        poll_interval: Time between polling attempts (default 5s)

    Returns:
        DownloadsResult with list of files, count, and status message
    """
    client = get_client()
    elapsed = 0.0

    while elapsed < timeout_seconds:
        try:
            response = client.sessions.downloads.list(session_id)
            zip_data = response.read()

            # Check for empty or invalid ZIP
            if len(zip_data) < MIN_ZIP_SIZE:
                await asyncio.sleep(poll_interval)
                elapsed += poll_interval
                continue

            # Extract files from ZIP
            files: list[DownloadedFile] = []
            with zipfile.ZipFile(io.BytesIO(zip_data), "r") as zf:
                for info in zf.infolist():
                    # Skip directories and hidden files
                    if info.is_dir() or info.filename.startswith("."):
                        continue

                    # Read file content and encode as base64
                    content = zf.read(info.filename)
                    files.append(
                        DownloadedFile(
                            filename=info.filename,
                            content_base64=base64.b64encode(content).decode("ascii"),
                            size_bytes=len(content),
                        )
                    )

            if files:
                return DownloadsResult(
                    files=files,
                    total_files=len(files),
                    message=f"Successfully retrieved {len(files)} file(s)",
                )

            # No files yet, keep polling
            await asyncio.sleep(poll_interval)
            elapsed += poll_interval

        except Exception as e:
            # Handle 404 (no downloads yet) by continuing to poll
            if "404" in str(e):
                await asyncio.sleep(poll_interval)
                elapsed += poll_interval
                continue
            # Re-raise other exceptions
            raise

    return DownloadsResult(
        files=[],
        total_files=0,
        message=f"No downloads found within {timeout_seconds} seconds",
    )


async def browserbase_stop_session(
    session_id: Annotated[str, "The Browserbase session ID to stop"],
) -> bool:
    """
    Stop a Browserbase session to release resources and reduce costs.

    Call this when you are done with a session to clean up cloud resources.

    Args:
        session_id: The Browserbase session ID from browserbase_create_session

    Returns:
        True if session stopped successfully, False on any error
    """
    try:
        if not BROWSERBASE_PROJECT_ID:
            return False
        client = get_client()
        client.sessions.update(
            session_id, project_id=BROWSERBASE_PROJECT_ID, status="REQUEST_RELEASE"
        )
        return True
    except Exception:
        return False
