"""Unit tests for Browserbase tools.

Per TDD section 14.1 - Tests for browserbase_create_session, configure_downloads,
get_downloads, and stop_session.
"""

import pytest
from unittest.mock import patch, MagicMock


class TestBrowserbaseCreateSession:
    """Tests for browserbase_create_session function."""

    @pytest.mark.asyncio
    async def test_create_session_success(
        self, mock_browserbase_client: MagicMock
    ) -> None:
        """Test successful session creation returns session_id and cdp_url."""
        with patch(
            "clerkiq_playwright_mcp.tools.browserbase.get_client",
            return_value=mock_browserbase_client,
        ), patch(
            "clerkiq_playwright_mcp.tools.browserbase.BROWSERBASE_PROJECT_ID",
            "test-project-id",
        ):
            from clerkiq_playwright_mcp.tools.browserbase import (
                browserbase_create_session,
            )

            result = await browserbase_create_session()

            assert result.session_id == "test-session-id"
            assert result.cdp_url == "wss://test.browserbase.com/connect"
            assert result.live_url == "https://test.browserbase.com/live/test-session-id"

            # Verify create was called with expected defaults
            mock_browserbase_client.sessions.create.assert_called_once()
            call_kwargs = mock_browserbase_client.sessions.create.call_args.kwargs
            assert call_kwargs["project_id"] == "test-project-id"
            assert call_kwargs["proxies"] is True
            assert call_kwargs["timeout"] == 1800
            assert call_kwargs["keep_alive"] is True

    @pytest.mark.asyncio
    async def test_create_session_custom_params(
        self, mock_browserbase_client: MagicMock
    ) -> None:
        """Test session creation with custom parameters (proxies=False, custom timeout)."""
        with patch(
            "clerkiq_playwright_mcp.tools.browserbase.get_client",
            return_value=mock_browserbase_client,
        ), patch(
            "clerkiq_playwright_mcp.tools.browserbase.BROWSERBASE_PROJECT_ID",
            "test-project-id",
        ):
            from clerkiq_playwright_mcp.tools.browserbase import (
                browserbase_create_session,
            )

            result = await browserbase_create_session(
                proxies=False,
                solve_captchas=False,
                timeout_seconds=600,
            )

            assert result.session_id == "test-session-id"
            assert result.cdp_url == "wss://test.browserbase.com/connect"

            # Verify create was called with custom parameters
            mock_browserbase_client.sessions.create.assert_called_once()
            call_kwargs = mock_browserbase_client.sessions.create.call_args.kwargs
            assert call_kwargs["proxies"] is False
            assert call_kwargs["timeout"] == 600
            # Check browser_settings has solve_captchas=False
            # BrowserSettings is a TypedDict, so it's a dict
            browser_settings = call_kwargs["browser_settings"]
            assert browser_settings["solve_captchas"] is False

    @pytest.mark.asyncio
    async def test_create_session_missing_api_key(self) -> None:
        """Test ValueError is raised when BROWSERBASE_API_KEY is not set."""
        with patch(
            "clerkiq_playwright_mcp.tools.browserbase.BROWSERBASE_API_KEY",
            None,
        ), patch(
            "clerkiq_playwright_mcp.tools.browserbase.BROWSERBASE_PROJECT_ID",
            "test-project-id",
        ):
            from clerkiq_playwright_mcp.tools.browserbase import (
                browserbase_create_session,
            )

            with pytest.raises(ValueError, match="BROWSERBASE_API_KEY"):
                await browserbase_create_session()

    @pytest.mark.asyncio
    async def test_create_session_missing_project_id(
        self, mock_browserbase_client: MagicMock
    ) -> None:
        """Test ValueError is raised when BROWSERBASE_PROJECT_ID is not set."""
        with patch(
            "clerkiq_playwright_mcp.tools.browserbase.get_client",
            return_value=mock_browserbase_client,
        ), patch(
            "clerkiq_playwright_mcp.tools.browserbase.BROWSERBASE_PROJECT_ID",
            None,
        ):
            from clerkiq_playwright_mcp.tools.browserbase import (
                browserbase_create_session,
            )

            with pytest.raises(ValueError, match="BROWSERBASE_PROJECT_ID"):
                await browserbase_create_session()


class TestBrowserbaseConfigureDownloads:
    """Tests for browserbase_configure_downloads function."""

    @pytest.mark.asyncio
    async def test_configure_downloads_success(
        self, mock_websocket: MagicMock
    ) -> None:
        """Test successful download configuration verifies CDP command sent correctly."""
        import json

        with patch(
            "clerkiq_playwright_mcp.tools.browserbase.websockets.connect"
        ) as mock_connect:
            # Setup mock context manager
            mock_connect.return_value.__aenter__.return_value = mock_websocket
            mock_connect.return_value.__aexit__.return_value = None

            from clerkiq_playwright_mcp.tools.browserbase import (
                browserbase_configure_downloads,
            )

            result = await browserbase_configure_downloads(
                cdp_url="wss://test.browserbase.com/connect"
            )

            assert result is True

            # Verify connect was called with correct URL
            mock_connect.assert_called_once_with("wss://test.browserbase.com/connect")

            # Verify CDP command was sent correctly
            mock_websocket.send.assert_called_once()
            sent_data = mock_websocket.send.call_args[0][0]
            sent_command = json.loads(sent_data)

            assert sent_command["id"] == 1
            assert sent_command["method"] == "Browser.setDownloadBehavior"
            assert sent_command["params"]["behavior"] == "allow"
            assert sent_command["params"]["downloadPath"] == "downloads"
            assert sent_command["params"]["eventsEnabled"] is True

    @pytest.mark.asyncio
    async def test_configure_downloads_error_response(
        self, mock_websocket: MagicMock
    ) -> None:
        """Test download configuration handles CDP error response correctly."""
        # Return an error response from CDP
        mock_websocket.recv.return_value = '{"id": 1, "error": {"code": -32000, "message": "Test error"}}'

        with patch(
            "clerkiq_playwright_mcp.tools.browserbase.websockets.connect"
        ) as mock_connect:
            mock_connect.return_value.__aenter__.return_value = mock_websocket
            mock_connect.return_value.__aexit__.return_value = None

            from clerkiq_playwright_mcp.tools.browserbase import (
                browserbase_configure_downloads,
            )

            result = await browserbase_configure_downloads(
                cdp_url="wss://test.browserbase.com/connect"
            )

            assert result is False

    @pytest.mark.asyncio
    async def test_configure_downloads_connection_error(self) -> None:
        """Test download configuration handles websocket connection failure."""
        import websockets.exceptions

        with patch(
            "clerkiq_playwright_mcp.tools.browserbase.websockets.connect"
        ) as mock_connect:
            # Simulate connection failure
            mock_connect.side_effect = websockets.exceptions.WebSocketException(
                "Connection refused"
            )

            from clerkiq_playwright_mcp.tools.browserbase import (
                browserbase_configure_downloads,
            )

            result = await browserbase_configure_downloads(
                cdp_url="wss://test.browserbase.com/connect"
            )

            assert result is False
