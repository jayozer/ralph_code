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


class TestBrowserbaseGetDownloads:
    """Tests for browserbase_get_downloads function."""

    @pytest.mark.asyncio
    async def test_get_downloads_success(
        self, mock_browserbase_client: MagicMock, sample_zip_with_pdf: bytes
    ) -> None:
        """Test successful download retrieval verifies ZIP extraction and base64 encoding."""
        import base64

        # Configure mock to return a ZIP with a PDF
        mock_browserbase_client.sessions.downloads.list.return_value.read.return_value = (
            sample_zip_with_pdf
        )

        with patch(
            "clerkiq_playwright_mcp.tools.browserbase.get_client",
            return_value=mock_browserbase_client,
        ):
            from clerkiq_playwright_mcp.tools.browserbase import (
                browserbase_get_downloads,
            )

            result = await browserbase_get_downloads(
                session_id="test-session-id",
                timeout_seconds=10,
                poll_interval=0.1,
            )

            assert result.total_files == 1
            assert len(result.files) == 1
            assert result.files[0].filename == "test-document.pdf"
            assert result.files[0].size_bytes > 0
            assert "Successfully retrieved 1 file" in result.message

            # Verify base64 encoding is valid
            decoded = base64.b64decode(result.files[0].content_base64)
            assert decoded.startswith(b"%PDF-1.4")

    @pytest.mark.asyncio
    async def test_get_downloads_empty(
        self, mock_browserbase_client: MagicMock, empty_zip: bytes
    ) -> None:
        """Test get downloads handles no downloads case (empty ZIP or timeout)."""
        # Configure mock to return an empty ZIP
        mock_browserbase_client.sessions.downloads.list.return_value.read.return_value = (
            empty_zip
        )

        with patch(
            "clerkiq_playwright_mcp.tools.browserbase.get_client",
            return_value=mock_browserbase_client,
        ):
            from clerkiq_playwright_mcp.tools.browserbase import (
                browserbase_get_downloads,
            )

            result = await browserbase_get_downloads(
                session_id="test-session-id",
                timeout_seconds=1,
                poll_interval=0.1,
            )

            assert result.total_files == 0
            assert len(result.files) == 0
            assert "No downloads found" in result.message

    @pytest.mark.asyncio
    async def test_get_downloads_404_then_success(
        self, mock_browserbase_client: MagicMock, sample_zip_with_pdf: bytes
    ) -> None:
        """Test get downloads polls and handles 404 before success."""
        # First call raises 404, second call returns ZIP
        call_count = 0

        def mock_read() -> bytes:
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                raise Exception("404 Not Found")
            return sample_zip_with_pdf

        mock_browserbase_client.sessions.downloads.list.return_value.read.side_effect = (
            mock_read
        )

        with patch(
            "clerkiq_playwright_mcp.tools.browserbase.get_client",
            return_value=mock_browserbase_client,
        ):
            from clerkiq_playwright_mcp.tools.browserbase import (
                browserbase_get_downloads,
            )

            result = await browserbase_get_downloads(
                session_id="test-session-id",
                timeout_seconds=10,
                poll_interval=0.1,
            )

            # Should succeed after polling past the 404
            assert result.total_files == 1
            assert len(result.files) == 1
            assert result.files[0].filename == "test-document.pdf"
            assert "Successfully retrieved 1 file" in result.message
            # Verify it polled at least twice
            assert call_count >= 2


class TestBrowserbaseStopSession:
    """Tests for browserbase_stop_session function."""

    @pytest.mark.asyncio
    async def test_stop_session_success(
        self, mock_browserbase_client: MagicMock
    ) -> None:
        """Test successful session stop verifies update called with REQUEST_RELEASE."""
        with patch(
            "clerkiq_playwright_mcp.tools.browserbase.get_client",
            return_value=mock_browserbase_client,
        ), patch(
            "clerkiq_playwright_mcp.tools.browserbase.BROWSERBASE_PROJECT_ID",
            "test-project-id",
        ):
            from clerkiq_playwright_mcp.tools.browserbase import (
                browserbase_stop_session,
            )

            result = await browserbase_stop_session(session_id="test-session-id")

            assert result is True

            # Verify update was called with correct parameters
            mock_browserbase_client.sessions.update.assert_called_once_with(
                "test-session-id",
                project_id="test-project-id",
                status="REQUEST_RELEASE",
            )

    @pytest.mark.asyncio
    async def test_stop_session_error(
        self, mock_browserbase_client: MagicMock
    ) -> None:
        """Test session stop handles API errors gracefully."""
        # Configure mock to raise an exception
        mock_browserbase_client.sessions.update.side_effect = Exception("API error")

        with patch(
            "clerkiq_playwright_mcp.tools.browserbase.get_client",
            return_value=mock_browserbase_client,
        ), patch(
            "clerkiq_playwright_mcp.tools.browserbase.BROWSERBASE_PROJECT_ID",
            "test-project-id",
        ):
            from clerkiq_playwright_mcp.tools.browserbase import (
                browserbase_stop_session,
            )

            result = await browserbase_stop_session(session_id="test-session-id")

            # Should return False on error, not raise
            assert result is False
